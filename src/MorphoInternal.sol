// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {PoolLib} from "./libraries/PoolLib.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {Constants} from "./libraries/Constants.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {InterestRatesLib} from "./libraries/InterestRatesLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {UserConfiguration} from "@aave-v3-core/protocol/libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {MorphoStorage} from "./MorphoStorage.sol";

/// @title MorphoInternal
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Abstract contract exposing `Morpho`'s internal functions.
abstract contract MorphoInternal is MorphoStorage {
    using PoolLib for IPool;
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using SafeTransferLib for ERC20;

    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /// INTERNAL ///

    /// @dev Creates a new market for the `underlying` token with a given `reserveFactor` (in bps) and a given `p2pIndexCursor` (in bps).
    function _createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        if (underlying == address(0)) revert Errors.AddressIsZero();
        if (p2pIndexCursor > PercentageMath.PERCENTAGE_FACTOR || reserveFactor > PercentageMath.PERCENTAGE_FACTOR) {
            revert Errors.ExceedsMaxBasisPoints();
        }

        DataTypes.ReserveData memory reserveData = _POOL.getReserveData(underlying);
        if (!reserveData.configuration.getActive()) revert Errors.MarketIsNotListedOnAave();

        Types.Market storage market = _market[underlying];

        if (market.isCreated()) revert Errors.MarketAlreadyCreated();

        Types.Indexes256 memory indexes;
        (indexes.supply.poolIndex, indexes.borrow.poolIndex) = _POOL.getCurrentPoolIndexes(underlying);
        indexes.supply.p2pIndex = WadRayMath.RAY;
        indexes.borrow.p2pIndex = WadRayMath.RAY;

        market.setIndexes(indexes);

        market.underlying = underlying;
        market.aToken = reserveData.aTokenAddress;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(underlying);

        ERC20(underlying).safeApprove(address(_POOL), type(uint256).max);

        emit Events.MarketCreated(
            underlying, reserveFactor, p2pIndexCursor, indexes.supply.poolIndex, indexes.borrow.poolIndex
            );
    }

    /// @dev Claims the fee for the `underlyings` and send it to the `_treasuryVault`.
    ///      Claiming on a market where there are some rewards might steal users' rewards.
    function _claimToTreasury(address[] calldata underlyings, uint256[] calldata amounts) internal {
        address treasuryVault = _treasuryVault;
        if (treasuryVault == address(0)) revert Errors.AddressIsZero();

        for (uint256 i; i < underlyings.length; ++i) {
            address underlying = underlyings[i];
            Types.Market storage market = _market[underlying];

            if (!market.isCreated()) continue;

            uint256 claimable = ERC20(underlying).balanceOf(address(this)) - market.idleSupply;
            uint256 claimed = Math.min(amounts[i], claimable);

            if (claimed == 0) continue;

            ERC20(underlying).safeTransfer(treasuryVault, claimed);
            emit Events.ReserveFeeClaimed(underlying, claimed);
        }
    }

    /// @dev Increases the peer-to-peer delta of `amount` on the `underlying` market.
    function _increaseP2PDeltas(address underlying, uint256 amount) internal {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        Types.Market storage market = _market[underlying];
        Types.Deltas memory deltas = market.deltas;
        uint256 poolSupplyIndex = indexes.supply.poolIndex;
        uint256 poolBorrowIndex = indexes.borrow.poolIndex;

        amount = Math.min(
            amount,
            Math.min(
                deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                    deltas.supply.scaledDeltaPool.rayMul(poolSupplyIndex)
                ),
                deltas.borrow.scaledTotalP2P.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
                    deltas.borrow.scaledDeltaPool.rayMul(poolBorrowIndex)
                )
            )
        );
        if (amount == 0) revert Errors.AmountIsZero();

        uint256 newSupplyDelta = deltas.supply.scaledDeltaPool + amount.rayDiv(poolSupplyIndex);
        uint256 newBorrowDelta = deltas.borrow.scaledDeltaPool + amount.rayDiv(poolBorrowIndex);

        market.deltas.supply.scaledDeltaPool = newSupplyDelta;
        market.deltas.borrow.scaledDeltaPool = newBorrowDelta;
        emit Events.P2PSupplyDeltaUpdated(underlying, newSupplyDelta);
        emit Events.P2PBorrowDeltaUpdated(underlying, newBorrowDelta);

        _POOL.borrowFromPool(underlying, amount);
        _POOL.supplyToPool(underlying, amount);

        emit Events.P2PDeltasIncreased(underlying, amount);
    }

    /// @dev Returns the hash of the EIP712 typed data.
    function _hashEIP712TypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(Constants.EIP712_MSG_PREFIX, _DOMAIN_SEPARATOR, structHash));
    }

    /// @notice Approves a `manager` to borrow/withdraw on behalf of the sender.
    /// @param manager The address of the manager.
    /// @param isAllowed Whether `manager` is allowed to manage `delegator`'s position or not.
    function _approveManager(address delegator, address manager, bool isAllowed) internal {
        _isManaging[delegator][manager] = isAllowed;
        emit Events.ManagerApproval(delegator, manager, isAllowed);
    }

    /// @dev Returns the total balance of `user` on the `underlying` market given `indexes`.
    /// @param scaledPoolBalance The scaled balance of the user on the pool.
    /// @param scaledP2PBalance The scaled balance of the user in peer-to-peer.
    /// @param indexes pool & peer-to-peer borrow.
    /// @return The total balance of `user` on the `underlying` market (in underlying).
    function _getUserBalanceFromIndexes(
        uint256 scaledPoolBalance,
        uint256 scaledP2PBalance,
        Types.MarketSideIndexes256 memory indexes
    ) internal pure returns (uint256) {
        return scaledPoolBalance.rayMul(indexes.poolIndex) + scaledP2PBalance.rayMul(indexes.p2pIndex);
    }

    /// @dev Returns the total supply balance of `user` on the `underlying` market given `indexes`.
    /// @param underlying The address of the underlying asset.
    /// @param user The address of the user.
    /// @param indexes pool & peer-to-peer borrow.
    /// @return The total supply balance of `user` on the `underlying` market (in underlying).
    function _getUserSupplyBalanceFromIndexes(
        address underlying,
        address user,
        Types.MarketSideIndexes256 memory indexes
    ) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        return _getUserBalanceFromIndexes(
            marketBalances.scaledPoolSupplyBalance(user), marketBalances.scaledP2PSupplyBalance(user), indexes
        );
    }

    /// @dev Returns the total borrow balance of `user` on the `underlying` market given `indexes`.
    /// @param underlying The address of the underlying asset.
    /// @param user The address of the user.
    /// @param indexes pool & peer-to-peer borrow.
    /// @return The total borrow balance of `user` on the `underlying` market (in underlying).
    function _getUserBorrowBalanceFromIndexes(
        address underlying,
        address user,
        Types.MarketSideIndexes256 memory indexes
    ) internal view returns (uint256) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        return _getUserBalanceFromIndexes(
            marketBalances.scaledPoolBorrowBalance(user), marketBalances.scaledP2PBorrowBalance(user), indexes
        );
    }

    /// @dev Returns the collateral balance of `user` on the `underlying` market a `poolSupplyIndex` (in underlying).
    function _getUserCollateralBalanceFromIndex(address underlying, address user, uint256 poolSupplyIndex)
        internal
        view
        returns (uint256)
    {
        return _marketBalances[underlying].scaledCollateralBalance(user).rayMulDown(poolSupplyIndex);
    }

    /// @notice Returns the hypothetical liquidity data of `user`.
    /// @param underlying The address of the underlying asset to borrow.
    /// @param user The address of the user to get liquidity data for.
    /// @param amountWithdrawn The hypothetical amount to withdraw on the `underlying` market.
    /// @param amountBorrowed The hypothetical amount to borrow on the `underlying` market.
    /// @return liquidityData The hypothetical liquidaty data of `user`.
    function _liquidityData(address underlying, address user, uint256 amountWithdrawn, uint256 amountBorrowed)
        internal
        view
        returns (Types.LiquidityData memory liquidityData)
    {
        Types.LiquidityVars memory vars;

        if (_E_MODE_CATEGORY_ID != 0) vars.eModeCategory = _POOL.getEModeCategoryData(_E_MODE_CATEGORY_ID);
        vars.morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        vars.oracle = IAaveOracle(_ADDRESSES_PROVIDER.getPriceOracle());
        vars.user = user;

        (liquidityData.collateral, liquidityData.borrowable, liquidityData.maxDebt) =
            _totalCollateralData(underlying, vars, amountWithdrawn);

        liquidityData.debt = _totalDebt(underlying, vars, amountBorrowed);
    }

    /// @dev Returns the collateral data for a given set of inputs.
    /// @dev The total collateral data is computed iterating through all user's collateral assets.
    /// @param assetWithdrawn The address of the underlying asset hypothetically withdrawn. Pass address(0) if no asset is withdrawn.
    /// @param vars The liquidity variables.
    /// @param amountWithdrawn The amount withdrawn on the `assetWithdrawn` market (if any).
    /// @return collateral The total collateral of `vars.user`.
    /// @return borrowable The total borrowable amount of `vars.user`.
    /// @return maxDebt The total maximum debt of `vars.user`.
    function _totalCollateralData(address assetWithdrawn, Types.LiquidityVars memory vars, uint256 amountWithdrawn)
        internal
        view
        returns (uint256 collateral, uint256 borrowable, uint256 maxDebt)
    {
        address[] memory userCollaterals = _userCollaterals[vars.user].values();

        for (uint256 i; i < userCollaterals.length; ++i) {
            (uint256 collateralSingle, uint256 borrowableSingle, uint256 maxDebtSingle) =
                _collateralData(userCollaterals[i], vars, userCollaterals[i] == assetWithdrawn ? amountWithdrawn : 0);

            collateral += collateralSingle;
            borrowable += borrowableSingle;
            maxDebt += maxDebtSingle;
        }
    }

    /// @dev Returns the debt data for a given set of inputs.
    /// @dev The total debt data is computed iterating through all user's borrow assets.
    /// @param assetBorrowed The address of the underlying asset borrowed. Pass address(0) if no asset is borrowed.
    /// @param vars The liquidity variables.
    /// @param amountBorrowed The amount borrowed on the `assetBorrowed` market (if any).
    /// @return debt The total debt of `vars.user`.
    function _totalDebt(address assetBorrowed, Types.LiquidityVars memory vars, uint256 amountBorrowed)
        internal
        view
        returns (uint256 debt)
    {
        address[] memory userBorrows = _userBorrows[vars.user].values();

        for (uint256 i; i < userBorrows.length; ++i) {
            debt += _debt(userBorrows[i], vars, userBorrows[i] == assetBorrowed ? amountBorrowed : 0);
        }
        if (assetBorrowed != address(0) && !_userBorrows[vars.user].contains(assetBorrowed)) {
            debt += _debt(assetBorrowed, vars, amountBorrowed);
        }
    }

    /// @dev Returns the collateral data for a given set of inputs.
    /// @param underlying The address of the underlying asset to borrow.
    /// @param vars The liquidity variables.
    /// @param amountWithdrawn The amount withdrawn on the `underlying` market (if any).
    /// @return collateral The collateral of `vars.user` on the `underlying` market.
    /// @return borrowable The borrowable amount of `vars.user` on the `underlying` market.
    /// @return maxDebt The maximum debt of `vars.user` on the `underlying` market.
    function _collateralData(address underlying, Types.LiquidityVars memory vars, uint256 amountWithdrawn)
        internal
        view
        returns (uint256 collateral, uint256 borrowable, uint256 maxDebt)
    {
        (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit) =
            _assetLiquidityData(underlying, vars);

        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);
        collateral = (
            _getUserCollateralBalanceFromIndex(underlying, vars.user, indexes.supply.poolIndex).zeroFloorSub(
                amountWithdrawn
            )
        ) * underlyingPrice / tokenUnit;

        borrowable = collateral.percentMulDown(ltv);
        maxDebt = collateral.percentMulDown(liquidationThreshold);
    }

    /// @dev Returns the debt value for a given set of inputs.
    /// @param underlying The address of the underlying asset to borrow.
    /// @param vars The liquidity variables.
    /// @param amountBorrowed The amount borrowed on the `underlying` market (if any).
    /// @return debtValue The debt value of `vars.user` on the `underlying` market.
    function _debt(address underlying, Types.LiquidityVars memory vars, uint256 amountBorrowed)
        internal
        view
        returns (uint256 debtValue)
    {
        (uint256 underlyingPrice,,, uint256 tokenUnit) = _assetLiquidityData(underlying, vars);

        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);
        debtValue = (
            (_getUserBorrowBalanceFromIndexes(underlying, vars.user, indexes.borrow) + amountBorrowed) * underlyingPrice
        ).divUp(tokenUnit);
    }

    /// @dev Returns the liquidity data for a given set of inputs.
    /// @param underlying The address of the underlying asset.
    /// @param vars The liquidity variables.
    /// @return underlyingPrice The price of the underlying asset (in base currency).
    /// @return ltv The loan to value of the underlying asset.
    /// @return liquidationThreshold The liquidation threshold of the underlying asset.
    /// @return tokenUnit The token unit of the underlying asset.
    function _assetLiquidityData(address underlying, Types.LiquidityVars memory vars)
        internal
        view
        returns (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit)
    {
        DataTypes.ReserveData memory reserveData = _POOL.getReserveData(underlying);
        DataTypes.ReserveConfigurationMap memory configuration = reserveData.configuration;
        ltv = configuration.getLtv();
        liquidationThreshold = configuration.getLiquidationThreshold();
        tokenUnit = configuration.getDecimals();

        unchecked {
            tokenUnit = 10 ** tokenUnit;
        }

        if (_E_MODE_CATEGORY_ID != 0 && _E_MODE_CATEGORY_ID == configuration.getEModeCategory()) {
            uint256 eModeUnderlyingPrice;
            if (vars.eModeCategory.priceSource != address(0)) {
                eModeUnderlyingPrice = vars.oracle.getAssetPrice(vars.eModeCategory.priceSource);
            }
            underlyingPrice = eModeUnderlyingPrice != 0 ? eModeUnderlyingPrice : vars.oracle.getAssetPrice(underlying);

            if (ltv != 0) ltv = vars.eModeCategory.ltv;
            liquidationThreshold = vars.eModeCategory.liquidationThreshold;
        } else {
            underlyingPrice = vars.oracle.getAssetPrice(underlying);
        }

        // If a LTV has been reduced to 0 on Aave v3, the other assets of the collateral are frozen.
        // In response, Morpho disables the asset as collateral and sets its liquidation threshold to 0.
        if (ltv == 0) liquidationThreshold = 0;
    }

    /// @dev Updates a `user`'s position in the data structure.
    /// @param poolToken The address of the pool token related to this market (aToken or variable debt token address).
    /// @param user The address of the user to update.
    /// @param poolBuckets The pool buckets.
    /// @param p2pBuckets The peer-to-peer buckets.
    /// @param onPool The new scaled balance on pool of the `user`.
    /// @param inP2P The new scaled balance in peer-to-peer of the `user`.
    /// @param demoting Whether the update is happening during a demoting process or not.
    function _updateInDS(
        address poolToken,
        address user,
        LogarithmicBuckets.BucketList storage poolBuckets,
        LogarithmicBuckets.BucketList storage p2pBuckets,
        uint256 onPool,
        uint256 inP2P,
        bool demoting
    ) internal {
        uint256 formerOnPool = poolBuckets.getValueOf(user);
        uint256 formerInP2P = p2pBuckets.getValueOf(user);

        if (onPool != formerOnPool) {
            IRewardsManager rewardsManager = _rewardsManager;
            if (address(rewardsManager) != address(0)) {
                rewardsManager.updateUserRewards(user, poolToken, formerOnPool);
            }

            poolBuckets.update(user, onPool, demoting);
        }

        if (inP2P != formerInP2P) p2pBuckets.update(user, inP2P, true);
    }

    /// @dev Updates a `user`'s supply position in the data structure.
    /// @param underlying The address of the underlying asset.
    /// @param user The address of the user to update.
    /// @param onPool The new scaled balance on pool of the `user`.
    /// @param inP2P The new scaled balance in peer-to-peer of the `user`.
    /// @param demoting Whether the update is happening during a demoting process or not.
    function _updateSupplierInDS(address underlying, address user, uint256 onPool, uint256 inP2P, bool demoting)
        internal
    {
        _updateInDS(
            _market[underlying].aToken,
            user,
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            onPool,
            inP2P,
            demoting
        );
        // No need to update the user's list of supplied assets,
        // as it cannot be used as collateral and thus there's no need to iterate over it.
    }

    /// @dev Updates a `user`'s borrow position in the data structure.
    /// @param underlying The address of the underlying asset.
    /// @param user The address of the user to update.
    /// @param onPool The new scaled balance on pool of the `user`.
    /// @param inP2P The new scaled balance in peer-to-peer of the `user`.
    /// @param demoting Whether the update is happening during a demoting process or not.
    function _updateBorrowerInDS(address underlying, address user, uint256 onPool, uint256 inP2P, bool demoting)
        internal
    {
        _updateInDS(
            _market[underlying].variableDebtToken,
            user,
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            onPool,
            inP2P,
            demoting
        );
        if (onPool == 0 && inP2P == 0) _userBorrows[user].remove(underlying);
        else _userBorrows[user].add(underlying);
    }

    /// @dev Sets globally the pause status to `isPaused` on the `underlying` market.
    function _setPauseStatus(address underlying, bool isPaused) internal {
        Types.Market storage market = _market[underlying];

        market.setIsSupplyPaused(underlying, isPaused);
        market.setIsSupplyCollateralPaused(underlying, isPaused);
        market.setIsRepayPaused(underlying, isPaused);
        market.setIsWithdrawPaused(underlying, isPaused);
        market.setIsWithdrawCollateralPaused(underlying, isPaused);
        market.setIsLiquidateCollateralPaused(underlying, isPaused);
        market.setIsLiquidateBorrowPaused(underlying, isPaused);
        if (!market.pauseStatuses.isDeprecated) market.setIsBorrowPaused(underlying, isPaused);
    }

    /// @dev Updates the indexes of the `underlying` market and returns them.
    function _updateIndexes(address underlying) internal returns (Types.Indexes256 memory indexes) {
        bool cached;
        (cached, indexes) = _computeIndexes(underlying);

        if (!cached) {
            _market[underlying].setIndexes(indexes);

            emit Events.IndexesUpdated(
                underlying,
                indexes.supply.poolIndex,
                indexes.supply.p2pIndex,
                indexes.borrow.poolIndex,
                indexes.borrow.p2pIndex
                );
        }
    }

    /// @dev Computes the updated indexes of the `underlying` market (if not already updated) and returns them.
    function _computeIndexes(address underlying) internal view returns (bool cached, Types.Indexes256 memory indexes) {
        Types.Market storage market = _market[underlying];
        Types.Indexes256 memory lastIndexes = market.getIndexes();

        cached = block.timestamp == market.lastUpdateTimestamp;
        if (cached) return (true, lastIndexes);

        (indexes.supply.poolIndex, indexes.borrow.poolIndex) = _POOL.getCurrentPoolIndexes(underlying);

        (indexes.supply.p2pIndex, indexes.borrow.p2pIndex) = InterestRatesLib.computeP2PIndexes(
            Types.IndexesParams({
                lastSupplyIndexes: lastIndexes.supply,
                lastBorrowIndexes: lastIndexes.borrow,
                poolSupplyIndex: indexes.supply.poolIndex,
                poolBorrowIndex: indexes.borrow.poolIndex,
                reserveFactor: market.reserveFactor,
                p2pIndexCursor: market.p2pIndexCursor,
                deltas: market.deltas,
                proportionIdle: market.getProportionIdle()
            })
        );
    }

    /// @dev Returns the `user`'s health factor for the `underlying` market and hypothetical `withdrawnAmount`.
    function _getUserHealthFactor(address underlying, address user, uint256 withdrawnAmount)
        internal
        view
        returns (uint256)
    {
        Types.LiquidityData memory liquidityData = _liquidityData(underlying, user, withdrawnAmount, 0);

        return liquidityData.debt > 0 ? liquidityData.maxDebt.wadDiv(liquidityData.debt) : type(uint256).max;
    }

    /// @dev Calculates the amount to seize during a liquidation process.
    /// @param underlyingBorrowed The address of the underlying borrowed asset.
    /// @param underlyingCollateral The address of the underlying collateral asset.
    /// @param maxToLiquidate The maximum amount of `underlyingBorrowed` to liquidate.
    /// @param borrower The address of the borrower being liquidated.
    /// @param poolSupplyIndex The current pool supply index of the `underlyingCollateral` market.
    /// @return amountToLiquidate The amount of `underlyingBorrowed` to liquidate.
    /// @return amountToSeize The amount of `underlyingCollateral` to seize.
    function _calculateAmountToSeize(
        address underlyingBorrowed,
        address underlyingCollateral,
        uint256 maxToLiquidate,
        address borrower,
        uint256 poolSupplyIndex
    ) internal view returns (uint256 amountToLiquidate, uint256 amountToSeize) {
        amountToLiquidate = maxToLiquidate;
        DataTypes.ReserveConfigurationMap memory collateralConfig = _POOL.getConfiguration(underlyingCollateral);
        uint256 liquidationBonus = collateralConfig.getLiquidationBonus();
        uint256 collateralTokenUnit = collateralConfig.getDecimals();
        uint256 borrowTokenUnit = _POOL.getConfiguration(underlyingBorrowed).getDecimals();

        unchecked {
            collateralTokenUnit = 10 ** collateralTokenUnit;
            borrowTokenUnit = 10 ** borrowTokenUnit;
        }

        IAaveOracle oracle = IAaveOracle(_ADDRESSES_PROVIDER.getPriceOracle());
        uint256 borrowPrice = oracle.getAssetPrice(underlyingBorrowed);
        uint256 collateralPrice = oracle.getAssetPrice(underlyingCollateral);

        amountToSeize = ((amountToLiquidate * borrowPrice * collateralTokenUnit) / (borrowTokenUnit * collateralPrice))
            .percentMul(liquidationBonus);

        uint256 collateralBalance = _getUserCollateralBalanceFromIndex(underlyingCollateral, borrower, poolSupplyIndex);

        if (amountToSeize > collateralBalance) {
            amountToSeize = collateralBalance;
            amountToLiquidate = (
                (collateralBalance * collateralPrice * borrowTokenUnit) / (borrowPrice * collateralTokenUnit)
            ).percentDiv(liquidationBonus);
        }
    }
}
