// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {MorphoStorage} from "./MorphoStorage.sol";

import {
    Types,
    Events,
    Errors,
    MarketLib,
    MarketBalanceLib,
    MarketMaskLib,
    PoolInteractions,
    InterestRatesModel,
    WadRayMath,
    Math,
    PercentageMath,
    DataTypes,
    ReserveConfiguration,
    UserConfiguration,
    ThreeHeapOrdering
} from "./libraries/Libraries.sol";
import {
    IPool, IPriceOracleGetter, IVariableDebtToken, IAToken, IPriceOracleSentinel
} from "./interfaces/Interfaces.sol";

abstract contract MorphoInternal is MorphoStorage {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using MarketMaskLib for Types.UserMarkets;
    using WadRayMath for uint256;
    using Math for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using PoolInteractions for IPool;

    /// @notice Prevents to update a market not created yet.
    /// @param _poolToken The address of the market to check.
    modifier isMarketCreated(address _poolToken) {
        if (!_market[_poolToken].isCreated()) revert Errors.MarketNotCreated();
        _;
    }

    function _decodeId(uint256 _id) internal pure returns (address underlying, Types.PositionType positionType) {
        underlying = address(uint160(_id));
        positionType = Types.PositionType(_id & 0xf);
    }

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param user The address of the user.
    /// @param poolToken The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalance(address poolToken, address user) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Market storage market = _market[poolToken];
        return marketBalances.scaledP2PSupplyBalance(user).rayMul(market.p2pSupplyIndex)
            + marketBalances.scaledPoolSupplyBalance(user).rayMul(market.poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param user The address of the user.
    /// @param poolToken The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalance(address poolToken, address user) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Market storage market = _market[poolToken];
        return marketBalances.scaledP2PBorrowBalance(user).rayMul(market.p2pBorrowIndex)
            + marketBalances.scaledPoolBorrowBalance(user).rayMul(market.poolBorrowIndex);
    }

    /// @dev Calculates the value of the collateral.
    /// @param poolToken The pool token to calculate the value for.
    /// @param user The user address.
    /// @param underlyingPrice The underlying price.
    /// @param tokenUnit The token unit.
    function _collateralValue(address poolToken, address user, uint256 underlyingPrice, uint256 tokenUnit)
        internal
        view
        returns (uint256)
    {
        return (_marketBalances[poolToken].scaledCollateralBalance(user) * underlyingPrice) / tokenUnit; // TODO: Multiply by an index or make collateral balance unscaled
    }

    /// @dev Calculates the value of the debt.
    /// @param poolToken The pool token to calculate the value for.
    /// @param user The user address.
    /// @param underlyingPrice The underlying price.
    /// @param tokenUnit The token unit.
    function _debtValue(address poolToken, address user, uint256 underlyingPrice, uint256 tokenUnit)
        internal
        view
        returns (uint256)
    {
        return (_getUserBorrowBalance(poolToken, user) * underlyingPrice).divUp(tokenUnit);
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @param user The user address.
    /// @param poolToken The pool token that is being borrowed or withdrawn.
    /// @param amountWithdrawn The amount that is being withdrawn.
    /// @param amountBorrowed The amount that is being borrowed.
    /// @return liquidityData The struct containing health factor, collateral, debt, ltv, liquidation threshold values.
    function _liquidityData(address user, address poolToken, uint256 amountWithdrawn, uint256 amountBorrowed)
        internal
        view
        returns (Types.LiquidityData memory liquidityData)
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(_addressesProvider.getPriceOracle());
        Types.UserMarkets memory userMarkets = _userMarkets[user];
        DataTypes.UserConfigurationMap memory morphoPoolConfig = _pool.getUserConfiguration(address(this));

        uint256 poolTokensLength = _marketsCreated.length;

        for (uint256 i; i < poolTokensLength; ++i) {
            address currentMarket = _marketsCreated[i];

            if (userMarkets.isSupplyingOrBorrowing(_market[currentMarket].borrowMask)) {
                uint256 withdrawnSingle;
                uint256 borrowedSingle;

                if (poolToken == currentMarket) {
                    withdrawnSingle = amountWithdrawn;
                    borrowedSingle = amountBorrowed;
                }
                // else {
                //     _updateIndexes(currentMarket);
                // }

                Types.AssetLiquidityData memory assetLiquidityData =
                    _assetLiquidityData(_market[currentMarket].underlying, oracle, morphoPoolConfig);
                Types.LiquidityData memory liquidityDataSingle = _liquidityDataSingle(
                    currentMarket, user, userMarkets, assetLiquidityData, withdrawnSingle, borrowedSingle
                );
                liquidityData.collateral += liquidityDataSingle.collateral;
                liquidityData.maxDebt += liquidityDataSingle.maxDebt;
                liquidityData.liquidationThresholdValue += liquidityDataSingle.liquidationThresholdValue;
                liquidityData.debt += liquidityDataSingle.debt;
            }
        }
    }

    function _liquidityDataSingle(
        address poolToken,
        address user,
        Types.UserMarkets memory userMarkets,
        Types.AssetLiquidityData memory assetLiquidityData,
        uint256 amountBorrowed,
        uint256 amountWithdrawn
    ) internal view returns (Types.LiquidityData memory liquidityData) {
        Types.Market storage market = _market[poolToken];

        if (userMarkets.isBorrowing(market.borrowMask)) {
            liquidityData.debt +=
                _debtValue(poolToken, user, assetLiquidityData.underlyingPrice, assetLiquidityData.tokenUnit);
        }

        // Cache current asset collateral value.
        uint256 assetCollateralValue;
        if (userMarkets.isSupplying(market.borrowMask)) {
            assetCollateralValue =
                _collateralValue(poolToken, user, assetLiquidityData.underlyingPrice, assetLiquidityData.tokenUnit);
            liquidityData.collateral += assetCollateralValue;
            // Calculate LTV for borrow.
            liquidityData.maxDebt += assetCollateralValue.percentMul(assetLiquidityData.ltv);
        }

        // Update debt variable for borrowed token.
        if (amountBorrowed > 0) {
            liquidityData.debt +=
                (amountBorrowed * assetLiquidityData.underlyingPrice).divUp(assetLiquidityData.tokenUnit);
        }

        // Update LT variable for withdraw.
        if (assetCollateralValue > 0) {
            liquidityData.liquidationThresholdValue +=
                assetCollateralValue.percentMul(assetLiquidityData.liquidationThreshold);
        }

        // Subtract withdrawn amount from liquidation threshold and collateral.
        if (amountWithdrawn > 0) {
            uint256 withdrawn = (amountWithdrawn * assetLiquidityData.underlyingPrice) / assetLiquidityData.tokenUnit;
            liquidityData.collateral -= withdrawn;
            liquidityData.liquidationThresholdValue -= withdrawn.percentMul(assetLiquidityData.liquidationThreshold);
            liquidityData.maxDebt -= withdrawn.percentMul(assetLiquidityData.ltv);
        }
    }

    function _assetLiquidityData(
        address underlying,
        IPriceOracleGetter oracle,
        DataTypes.UserConfigurationMap memory morphoPoolConfig
    ) internal view returns (Types.AssetLiquidityData memory assetLiquidityData) {
        assetLiquidityData.underlyingPrice = oracle.getAssetPrice(underlying);

        (assetLiquidityData.ltv, assetLiquidityData.liquidationThreshold,, assetLiquidityData.decimals,,) =
            _pool.getConfiguration(underlying).getParams();

        // LTV should be zero if Morpho has not enabled this asset as collateral
        if (!morphoPoolConfig.isUsingAsCollateral(_pool.getReserveData(underlying).id)) {
            assetLiquidityData.ltv = 0;
        }

        // If a LTV has been reduced to 0 on Aave v3, the other assets of the collateral are frozen.
        // In response, Morpho disables the asset as collateral and sets its liquidation threshold to 0.
        if (assetLiquidityData.ltv == 0) {
            assetLiquidityData.liquidationThreshold = 0;
        }

        unchecked {
            assetLiquidityData.tokenUnit = 10 ** assetLiquidityData.decimals;
        }
    }

    function _updateInDS(
        address, // Note: token unused for now until more functionality added in
        address user,
        ThreeHeapOrdering.HeapArray storage marketOnPool,
        ThreeHeapOrdering.HeapArray storage marketInP2P,
        uint256 onPool,
        uint256 inP2P
    ) internal {
        uint256 formerOnPool = marketOnPool.getValueOf(user);

        if (onPool != formerOnPool) {
            // if (address(rewardsManager) != address(0))
            //     rewardsManager.updateUserAssetAndAccruedRewards(
            //         rewardsController,
            //         user,
            //         token,
            //         formerOnPool,
            //         IScaledBalanceToken(token).scaledTotalSupply()
            //     );
            marketOnPool.update(user, formerOnPool, onPool, _maxSortedUsers);
        }
        marketInP2P.update(user, marketInP2P.getValueOf(user), inP2P, _maxSortedUsers);
    }

    function _updateSupplierInDS(address poolToken, address user, uint256 onPool, uint256 inP2P) internal {
        _updateInDS(
            poolToken,
            user,
            _marketBalances[poolToken].poolSuppliers,
            _marketBalances[poolToken].p2pSuppliers,
            onPool,
            inP2P
        );
    }

    function _updateBorrowerInDS(address poolToken, address user, uint256 onPool, uint256 inP2P) internal {
        _updateInDS(
            _market[poolToken].variableDebtToken,
            user,
            _marketBalances[poolToken].poolBorrowers,
            _marketBalances[poolToken].p2pBorrowers,
            onPool,
            inP2P
        );
    }

    function _setPauseStatus(address poolToken, bool isPaused) internal {
        Types.PauseStatuses storage pauseStatuses = _market[poolToken].pauseStatuses;

        pauseStatuses.isSupplyPaused = isPaused;
        pauseStatuses.isBorrowPaused = isPaused;
        pauseStatuses.isWithdrawPaused = isPaused;
        pauseStatuses.isRepayPaused = isPaused;
        pauseStatuses.isLiquidateCollateralPaused = isPaused;
        pauseStatuses.isLiquidateBorrowPaused = isPaused;

        emit Events.IsSupplyPausedSet(poolToken, isPaused);
        emit Events.IsBorrowPausedSet(poolToken, isPaused);
        emit Events.IsWithdrawPausedSet(poolToken, isPaused);
        emit Events.IsRepayPausedSet(poolToken, isPaused);
        emit Events.IsLiquidateCollateralPausedSet(poolToken, isPaused);
        emit Events.IsLiquidateBorrowPausedSet(poolToken, isPaused);
    }

    function _computeIndexes(address poolToken)
        internal
        view
        returns (
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex,
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex
        )
    {
        Types.Market storage market = _market[poolToken];
        if (block.timestamp == market.lastUpdateTimestamp) {
            return (
                uint256(market.poolSupplyIndex),
                uint256(market.poolBorrowIndex),
                market.p2pSupplyIndex,
                market.p2pBorrowIndex
            );
        }

        (newPoolSupplyIndex, newPoolBorrowIndex) = _pool.getCurrentPoolIndexes(market.underlying);

        (newP2PSupplyIndex, newP2PBorrowIndex) = InterestRatesModel.computeP2PIndexes(
            Types.IRMParams({
                lastP2PSupplyIndex: market.p2pSupplyIndex,
                lastP2PBorrowIndex: market.p2pBorrowIndex,
                poolSupplyIndex: newPoolSupplyIndex,
                poolBorrowIndex: newPoolBorrowIndex,
                lastPoolSupplyIndex: market.poolSupplyIndex,
                lastPoolBorrowIndex: market.poolBorrowIndex,
                reserveFactor: market.reserveFactor,
                p2pIndexCursor: market.p2pIndexCursor,
                deltas: market.deltas
            })
        );
    }

    function _getCurrentPoolIndexes(address poolToken)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        IPool pool = _pool;
        address underlying = _market[poolToken].underlying;

        poolSupplyIndex = pool.getReserveNormalizedIncome(underlying);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlying);
    }

    function _borrowAllowed(address user, address poolToken, uint256 borrowedAmount) internal view returns (bool) {
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // In response, Morpho mirrors this behavior.
        address priceOracleSentinel = _addressesProvider.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            return false;
        }

        Types.LiquidityData memory values = _liquidityData(user, poolToken, 0, borrowedAmount);
        return values.debt <= values.maxDebt;
    }

    function _getUserHealthFactor(address user, address poolToken, uint256 withdrawnAmount)
        internal
        view
        returns (uint256)
    {
        // If the user is not borrowing any asset, return an infinite health factor.
        if (!_userMarkets[user].isBorrowingAny()) return type(uint256).max;

        Types.LiquidityData memory liquidityData = _liquidityData(user, poolToken, withdrawnAmount, 0);

        return liquidityData.debt > 0
            ? liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debt)
            : type(uint256).max;
    }

    function _withdrawAllowed(address user, address poolToken, uint256 withdrawnAmount) internal view returns (bool) {
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // For safety concerns and as a withdraw on Morpho can trigger a borrow on pool, Morpho prevents withdrawals in such circumstances.
        address priceOracleSentinel = _addressesProvider.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            return false;
        }

        return _getUserHealthFactor(user, poolToken, withdrawnAmount) >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    function _liquidationAllowed(address user, bool isDeprecated)
        internal
        view
        returns (bool liquidationAllowed, uint256 closeFactor)
    {
        if (isDeprecated) {
            liquidationAllowed = true;
            closeFactor = MAX_BASIS_POINTS; // Allow liquidation of the whole debt.
        } else {
            uint256 healthFactor = _getUserHealthFactor(user, address(0), 0);
            address priceOracleSentinel = _addressesProvider.getPriceOracleSentinel();

            if (priceOracleSentinel != address(0)) {
                liquidationAllowed = (
                    healthFactor < MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD
                        || (
                            IPriceOracleSentinel(priceOracleSentinel).isLiquidationAllowed()
                                && healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD
                        )
                );
            } else {
                liquidationAllowed = healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
            }

            if (liquidationAllowed) {
                closeFactor = healthFactor > MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD
                    ? DEFAULT_LIQUIDATION_CLOSE_FACTOR
                    : MAX_LIQUIDATION_CLOSE_FACTOR;
            }
        }
    }
}
