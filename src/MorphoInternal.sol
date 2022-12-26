// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {
    IPool, IPriceOracleGetter, IVariableDebtToken, IAToken, IPriceOracleSentinel
} from "./interfaces/Interfaces.sol";

import {
    MarketLib,
    MarketBalanceLib,
    PoolInteractions,
    InterestRatesModel,
    WadRayMath,
    Math,
    PercentageMath,
    SafeCast,
    DataTypes,
    ReserveConfiguration,
    UserConfiguration,
    ThreeHeapOrdering
} from "./libraries/Libraries.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MorphoStorage} from "./MorphoStorage.sol";

abstract contract MorphoInternal is MorphoStorage {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using PoolInteractions for IPool;
    using EnumerableSet for EnumerableSet.AddressSet;

    using SafeCast for uint256;
    using WadRayMath for uint256;
    using Math for uint256;
    using PercentageMath for uint256;

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
        Types.IndexesMem memory indexes = _computeIndexes(poolToken);
        return _getUserSupplyBalanceFromIndexes(poolToken, user, indexes.poolSupplyIndex, indexes.p2pSupplyIndex);
    }

    function _getUserSupplyBalanceFromIndexes(
        address poolToken,
        address user,
        uint256 poolSupplyIndex,
        uint256 p2pSupplyIndex
    ) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        return marketBalances.scaledPoolSupplyBalance(user).rayMul(poolSupplyIndex)
            + marketBalances.scaledP2PSupplyBalance(user).rayMul(p2pSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param user The address of the user.
    /// @param poolToken The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalance(address poolToken, address user) internal view returns (uint256) {
        Types.IndexesMem memory indexes = _computeIndexes(poolToken);
        return _getUserBorrowBalanceFromIndexes(poolToken, user, indexes.poolBorrowIndex, indexes.p2pBorrowIndex);
    }

    function _getUserBorrowBalanceFromIndexes(
        address poolToken,
        address user,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex
    ) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        return marketBalances.scaledPoolBorrowBalance(user).rayMul(poolBorrowIndex)
            + marketBalances.scaledP2PBorrowBalance(user).rayMul(p2pBorrowIndex);
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @param poolToken The pool token that is being borrowed or withdrawn.
    /// @param user The user address.
    /// @param amountWithdrawn The amount that is being withdrawn.
    /// @param amountBorrowed The amount that is being borrowed.
    /// @return liquidityData The struct containing health factor, collateral, debt, ltv, liquidation threshold values.
    function _liquidityData(address poolToken, address user, uint256 amountWithdrawn, uint256 amountBorrowed)
        internal
        view
        returns (Types.LiquidityData memory liquidityData)
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(_addressesProvider.getPriceOracle());
        address[] memory userCollaterals = _userCollaterals[user].values();
        address[] memory userBorrows = _userBorrows[user].values();
        DataTypes.UserConfigurationMap memory morphoPoolConfig = _pool.getUserConfiguration(address(this));

        for (uint256 i; i < userCollaterals.length; ++i) {
            Types.IndexesMem memory indexes = _computeIndexes(userCollaterals[i]);
            (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit) =
                _assetLiquidityData(_market[userCollaterals[i]].underlying, oracle, morphoPoolConfig);
            (uint256 collateralValue, uint256 maxDebtValue, uint256 liquidationThresholdValue) =
            _liquidityDataCollateral(
                userCollaterals[i],
                user,
                underlyingPrice,
                ltv,
                liquidationThreshold,
                tokenUnit,
                indexes.poolSupplyIndex,
                poolToken == userCollaterals[i] ? amountWithdrawn : 0
            );
            liquidityData.collateral += collateralValue;
            liquidityData.maxDebt += maxDebtValue;
            liquidityData.liquidationThresholdValue += liquidationThresholdValue;
        }

        for (uint256 i; i < userBorrows.length; ++i) {
            Types.IndexesMem memory indexes = _computeIndexes(userBorrows[i]);

            (uint256 underlyingPrice,,, uint256 tokenUnit) =
                _assetLiquidityData(_market[userBorrows[i]].underlying, oracle, morphoPoolConfig);
            liquidityData.debt += _liquidityDataDebt(
                userBorrows[i],
                user,
                underlyingPrice,
                tokenUnit,
                indexes.poolBorrowIndex,
                indexes.p2pBorrowIndex,
                poolToken == userBorrows[i] ? amountBorrowed : 0
            );
        }
    }

    function _liquidityDataCollateral(
        address poolToken,
        address user,
        uint256 underlyingPrice,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 tokenUnit,
        uint256 poolSupplyIndex,
        uint256 amountWithdrawn
    ) internal view returns (uint256 collateral, uint256 maxDebt, uint256 liquidationThresholdValue) {
        collateral = (
            (_marketBalances[poolToken].scaledCollateralBalance(user).rayMul(poolSupplyIndex) - amountWithdrawn)
                * underlyingPrice / tokenUnit
        );

        // Calculate LTV for borrow.
        maxDebt += collateral.percentMul(ltv);

        // Update LT variable for withdraw.
        liquidationThresholdValue += collateral.percentMul(liquidationThreshold);
    }

    function _liquidityDataDebt(
        address poolToken,
        address user,
        uint256 underlyingPrice,
        uint256 tokenUnit,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex,
        uint256 amountBorrowed
    ) internal view returns (uint256 debt) {
        debt = (
            (_getUserBorrowBalanceFromIndexes(poolToken, user, poolBorrowIndex, p2pBorrowIndex) + amountBorrowed)
                * underlyingPrice
        ).divUp(tokenUnit);
    }

    function _assetLiquidityData(
        address underlying,
        IPriceOracleGetter oracle,
        DataTypes.UserConfigurationMap memory morphoPoolConfig
    ) internal view returns (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit) {
        underlyingPrice = oracle.getAssetPrice(underlying);

        uint256 decimals;

        (ltv, liquidationThreshold,, decimals,,) = _pool.getConfiguration(underlying).getParams();

        // LTV should be zero if Morpho has not enabled this asset as collateral
        if (!morphoPoolConfig.isUsingAsCollateral(_pool.getReserveData(underlying).id)) {
            ltv = 0;
        }

        // If a LTV has been reduced to 0 on Aave v3, the other assets of the collateral are frozen.
        // In response, Morpho disables the asset as collateral and sets its liquidation threshold to 0.
        if (ltv == 0) {
            liquidationThreshold = 0;
        }

        unchecked {
            tokenUnit = 10 ** decimals;
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

    function _updateIndexes(address poolToken) internal returns (Types.IndexesMem memory indexes) {
        Types.Market storage market = _market[poolToken];
        indexes = _computeIndexes(poolToken);

        market.setIndexes(indexes);
    }

    function _computeIndexes(address poolToken) internal view returns (Types.IndexesMem memory indexes) {
        Types.Market storage market = _market[poolToken];
        if (block.timestamp == market.lastUpdateTimestamp) {
            return market.getIndexes();
        }

        (indexes.poolSupplyIndex, indexes.poolBorrowIndex) = _pool.getCurrentPoolIndexes(market.underlying);

        (indexes.p2pSupplyIndex, indexes.p2pBorrowIndex) = InterestRatesModel.computeP2PIndexes(
            Types.IRMParams({
                lastPoolSupplyIndex: market.indexes.poolSupplyIndex,
                lastPoolBorrowIndex: market.indexes.poolBorrowIndex,
                lastP2PSupplyIndex: market.indexes.p2pSupplyIndex,
                lastP2PBorrowIndex: market.indexes.p2pBorrowIndex,
                poolSupplyIndex: indexes.poolSupplyIndex,
                poolBorrowIndex: indexes.poolBorrowIndex,
                reserveFactor: market.reserveFactor,
                p2pIndexCursor: market.p2pIndexCursor,
                deltas: market.deltas
            })
        );
    }

    function _getUserHealthFactor(address user, address poolToken, uint256 withdrawnAmount)
        internal
        view
        returns (uint256)
    {
        // If the user is not borrowing any asset, return an infinite health factor.
        if (_userBorrows[user].length() == 0) return type(uint256).max;

        Types.LiquidityData memory liquidityData = _liquidityData(poolToken, user, withdrawnAmount, 0);

        return liquidityData.debt > 0
            ? liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debt)
            : type(uint256).max;
    }
}
