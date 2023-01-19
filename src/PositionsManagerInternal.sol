// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPriceOracleGetter} from "@aave-v3-core/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave-v3-core/interfaces/IPriceOracleSentinel.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MatchingEngine} from "./MatchingEngine.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";

abstract contract PositionsManagerInternal is MatchingEngine {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function _validatePermission(address owner, address manager) internal view {
        if (!(owner == manager || _isManaging[owner][manager])) revert Errors.PermissionDenied();
    }

    function _validateInput(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        if (user == address(0)) revert Errors.AddressIsZero();
        if (amount == 0) revert Errors.AmountIsZero();

        market = _market[underlying];
        if (!market.isCreated()) revert Errors.MarketNotCreated();
    }

    function _validateManagerInput(address underlying, uint256 amount, address onBehalf, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        if (onBehalf == address(0)) revert Errors.AddressIsZero();

        market = _validateInput(underlying, amount, receiver);

        _validatePermission(onBehalf, msg.sender);
    }

    function _validateSupplyInput(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.pauseStatuses.isSupplyPaused) revert Errors.SupplyIsPaused();
    }

    function _validateSupplyCollateralInput(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.pauseStatuses.isSupplyCollateralPaused) revert Errors.SupplyCollateralIsPaused();
    }

    function _validateBorrowInput(address underlying, uint256 amount, address borrower, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, borrower, receiver);
        if (market.pauseStatuses.isBorrowPaused) revert Errors.BorrowIsPaused();

        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);
        if (!config.getBorrowingEnabled()) revert Errors.BorrowingNotEnabled();

        uint256 eMode = _POOL.getUserEMode(address(this));
        if (eMode != 0 && eMode != config.getEModeCategory()) revert Errors.InconsistentEMode();

        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // In response, Morpho mirrors this behavior.
        address priceOracleSentinel = _ADDRESSES_PROVIDER.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            revert Errors.PriceOracleSentinelBorrowDisabled();
        }
    }

    function _validateBorrow(address underlying, uint256 amount, address borrower) internal view {
        Types.LiquidityData memory values = _liquidityData(underlying, borrower, 0, amount);
        if (values.debt > values.borrowable) revert Errors.UnauthorizedBorrow();
    }

    function _validateWithdrawInput(address underlying, uint256 amount, address supplier, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, supplier, receiver);
        if (market.pauseStatuses.isWithdrawPaused) revert Errors.WithdrawIsPaused();

        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // For safety concerns and as a withdraw on Morpho can trigger a borrow on pool, Morpho prevents withdrawals in such circumstances.
        address priceOracleSentinel = _ADDRESSES_PROVIDER.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            revert Errors.PriceOracleSentinelBorrowPaused();
        }
    }

    function _validateWithdrawCollateralInput(address underlying, uint256 amount, address supplier, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, supplier, receiver);
        if (market.pauseStatuses.isWithdrawCollateralPaused) revert Errors.WithdrawCollateralIsPaused();
    }

    function _validateWithdrawCollateral(address underlying, uint256 amount, address supplier) internal view {
        if (_getUserHealthFactor(underlying, supplier, amount) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.UnauthorizedWithdraw();
        }
    }

    function _validateRepayInput(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.pauseStatuses.isRepayPaused) revert Errors.RepayIsPaused();
    }

    function _validateLiquidate(address underlyingBorrowed, address underlyingCollateral, address borrower)
        internal
        view
        returns (uint256 closeFactor)
    {
        Types.Market storage borrowMarket = _market[underlyingBorrowed];
        Types.Market storage collateralMarket = _market[underlyingCollateral];

        if (!collateralMarket.isCreated() || !borrowMarket.isCreated()) {
            revert Errors.MarketNotCreated();
        }
        if (collateralMarket.pauseStatuses.isLiquidateCollateralPaused) {
            revert Errors.LiquidateCollateralIsPaused();
        }
        if (borrowMarket.pauseStatuses.isLiquidateBorrowPaused) {
            revert Errors.LiquidateBorrowIsPaused();
        }
        if (
            !_userCollaterals[borrower].contains(underlyingCollateral)
                || !_userBorrows[borrower].contains(underlyingBorrowed)
        ) {
            revert Errors.UserNotMemberOfMarket();
        }

        if (borrowMarket.pauseStatuses.isDeprecated) {
            return Constants.MAX_CLOSE_FACTOR; // Allow liquidation of the whole debt.
        } else {
            uint256 healthFactor = _getUserHealthFactor(address(0), borrower, 0);
            address priceOracleSentinel = _ADDRESSES_PROVIDER.getPriceOracleSentinel();

            if (
                priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isLiquidationAllowed()
                    && healthFactor >= Constants.MIN_LIQUIDATION_THRESHOLD
            ) {
                revert Errors.UnauthorizedLiquidate();
            } else if (healthFactor >= Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
                revert Errors.UnauthorizedLiquidate();
            }

            closeFactor = healthFactor > Constants.MIN_LIQUIDATION_THRESHOLD
                ? Constants.DEFAULT_CLOSE_FACTOR
                : Constants.MAX_CLOSE_FACTOR;
        }
    }

    function _executeSupply(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.SupplyRepayVars memory vars) {
        Types.Deltas storage deltas = _market[underlying].deltas;
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];

        (vars.toRepay, amount) = _matchDelta(underlying, amount, indexes.borrow.poolIndex, true);

        uint256 promoted;
        (promoted, amount,) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.borrow.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteBorrowers
            }),
            deltas.borrow
        );
        vars.toRepay += promoted;

        vars.inP2P =
            _addToP2P(vars.toRepay, marketBalances.scaledP2PSupplyBalance(user), indexes.supply.p2pIndex, deltas.supply);
        (vars.toSupply, vars.onPool) =
            _addToPool(amount, marketBalances.scaledPoolSupplyBalance(user), indexes.supply.poolIndex);

        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P, false);

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    function _executeBorrow(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.BorrowWithdrawVars memory vars) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        (amount, vars.inP2P) = _borrowIdle(market, amount, vars.inP2P, indexes.borrow.p2pIndex);
        (vars.toWithdraw, amount) = _matchDelta(underlying, amount, indexes.supply.poolIndex, false);

        uint256 promoted;
        (promoted, amount,) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.supply.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteSuppliers
            }),
            deltas.supply
        );
        vars.toWithdraw += promoted;

        vars.inP2P = _addToP2P(vars.toWithdraw, vars.inP2P, indexes.borrow.p2pIndex, deltas.borrow);
        (vars.toBorrow, vars.onPool) = _addToPool(amount, vars.onPool, indexes.borrow.poolIndex);

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P, false);

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    function _executeRepay(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.SupplyRepayVars memory vars) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = _market[underlying].deltas;

        (vars.toRepay, amount, vars.onPool) =
            _subFromPool(amount, marketBalances.scaledPoolBorrowBalance(user), indexes.borrow.poolIndex);

        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user).zeroFloorSub(amount.rayDivUp(indexes.borrow.p2pIndex)); // In peer-to-peer borrow unit.

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P, false);

        if (amount == 0) {
            emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
            vars;
        }

        uint256 toRepayStep;
        (toRepayStep, amount) = _matchDelta(underlying, amount, indexes.borrow.poolIndex, true);
        vars.toRepay += toRepayStep;

        amount = _repayFee(underlying, amount, indexes);

        (toRepayStep, amount, maxLoops) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.borrow.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteBorrowers
            }),
            deltas.borrow
        );
        vars.toRepay += toRepayStep;

        vars.toSupply = _demoteRoutine(underlying, amount, maxLoops, indexes, _demoteSuppliers, deltas, false);
        vars.toSupply = _handleSupplyCap(underlying, vars.toSupply);

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    function _executeWithdraw(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.BorrowWithdrawVars memory vars) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        (vars.toWithdraw, amount, vars.onPool) =
            _subFromPool(amount, marketBalances.scaledPoolSupplyBalance(user), indexes.supply.poolIndex);

        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user).zeroFloorSub(amount.rayDivUp(indexes.supply.p2pIndex)); // In peer-to-peer supply unit.

        amount = _withdrawIdle(market, amount);

        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P, false);

        if (amount == 0) {
            emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
            return vars;
        }

        uint256 toWithdrawStep;
        (toWithdrawStep, amount) = _matchDelta(underlying, amount, indexes.supply.poolIndex, false);
        vars.toWithdraw += toWithdrawStep;

        (toWithdrawStep, amount, maxLoops) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.supply.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteSuppliers
            }),
            deltas.supply
        );
        vars.toWithdraw += toWithdrawStep;

        vars.toBorrow = _demoteRoutine(underlying, amount, maxLoops, indexes, _demoteBorrowers, deltas, true);

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    /// @notice Given variables from a market side, calculates the amount to supply/borrow and a new on pool amount.
    /// @param amount The amount to supply/borrow.
    /// @param onPool The current user's scaled on pool balance.
    /// @param poolIndex The current pool index.
    /// @return The amount to supply/borrow and the new on pool amount.
    function _addToPool(uint256 amount, uint256 onPool, uint256 poolIndex) internal pure returns (uint256, uint256) {
        if (amount == 0) return (0, onPool);

        return (
            amount,
            onPool + amount.rayDivDown(poolIndex) // In scaled balance.
        );
    }

    /// @notice Given variables from a market side, calculates the amount to repay/withdraw, the amount left to process, and a new on pool amount.
    /// @param amount The amount to repay/withdraw.
    /// @param onPool The current user's scaled on pool balance.
    /// @param poolIndex The current pool index.
    /// @return The amount to repay/withdraw, the amount left to process, and the new on pool amount.
    function _subFromPool(uint256 amount, uint256 onPool, uint256 poolIndex)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        if (onPool == 0) return (0, amount, onPool);

        uint256 toProcess = Math.min(onPool.rayMul(poolIndex), amount);

        return (
            toProcess,
            amount - toProcess,
            onPool.zeroFloorSub(toProcess.rayDivUp(poolIndex)) // In scaled balance.
        );
    }

    /// @notice Given variables from a market side, promotes users and calculates the amount to repay/withdraw from promote,
    ///         the amount left to process, and the number of loops left. Updates the market side delta accordingly.
    /// @param vars The variables for promotion.
    /// @param promotedDelta The market side delta to update.
    /// @return The amount to repay/withdraw from promote, the amount left to process, and the number of loops left.
    function _promoteRoutine(Types.PromoteVars memory vars, Types.MarketSideDelta storage promotedDelta)
        internal
        returns (uint256, uint256, uint256)
    {
        if (vars.amount == 0 || _market[vars.underlying].pauseStatuses.isP2PDisabled) {
            return (0, vars.amount, vars.maxLoops);
        }

        (uint256 promoted, uint256 loopsDone) = vars.promote(vars.underlying, vars.amount, vars.maxLoops); // In underlying.

        promotedDelta.scaledTotalP2P += promoted.rayDiv(vars.poolIndex);

        return (promoted, vars.amount - promoted, vars.maxLoops - loopsDone);
    }

    /// @notice Given variables from a market side, demotes users and calculates the amount to supply/borrow from demote.
    ///         Updates the market side delta accordingly.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param maxLoops The maximum number of loops to run.
    /// @param indexes The current indexes.
    /// @param demote The demote function.
    /// @param deltas The market side deltas to update.
    /// @param borrow Whether the market side is borrow.
    /// @return toProcess The amount to supply/borrow from demote.
    function _demoteRoutine(
        address underlying,
        uint256 amount,
        uint256 maxLoops,
        Types.Indexes256 memory indexes,
        function(address, uint256, uint256) returns (uint256) demote,
        Types.Deltas storage deltas,
        bool borrow
    ) internal returns (uint256) {
        if (amount == 0) return 0;

        uint256 demoted = demote(underlying, amount, maxLoops);

        Types.MarketSideIndexes256 memory demotedIndexes = borrow ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrow ? indexes.supply : indexes.borrow;
        Types.MarketSideDelta storage demotedDelta = borrow ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrow ? deltas.supply : deltas.borrow;

        // Increase the peer-to-peer supply delta.
        if (demoted < amount) {
            uint256 newScaledDeltaPool =
                demotedDelta.scaledDeltaPool + (amount - demoted).rayDiv(demotedIndexes.poolIndex);

            demotedDelta.scaledDeltaPool = newScaledDeltaPool;

            if (borrow) emit Events.P2PBorrowDeltaUpdated(underlying, newScaledDeltaPool);
            else emit Events.P2PSupplyDeltaUpdated(underlying, newScaledDeltaPool);
        }

        // Math.min as the last decimal might flip.
        demotedDelta.scaledTotalP2P = demotedDelta.scaledTotalP2P.zeroFloorSub(demoted.rayDiv(demotedIndexes.p2pIndex));
        counterDelta.scaledTotalP2P = counterDelta.scaledTotalP2P.zeroFloorSub(amount.rayDiv(counterIndexes.p2pIndex));

        return amount;
    }

    /// @notice Given variables from a market side, matches the delta and calculates the amount to supply/borrow from delta.
    ///         Updates the market side delta accordingly.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param poolIndex The current pool index.
    /// @param borrow Whether the market side is borrow.
    /// @return The amount to repay/withdraw and the amount left to process.
    function _matchDelta(address underlying, uint256 amount, uint256 poolIndex, bool borrow)
        internal
        returns (uint256, uint256)
    {
        Types.MarketSideDelta storage sideDelta =
            borrow ? _market[underlying].deltas.borrow : _market[underlying].deltas.supply;

        uint256 scaledDeltaPool = sideDelta.scaledDeltaPool;
        if (scaledDeltaPool == 0) return (0, amount);

        uint256 matchedDelta = Math.min(scaledDeltaPool.rayMulUp(poolIndex), amount); // In underlying.
        uint256 newScaledDeltaPool = scaledDeltaPool.zeroFloorSub(matchedDelta.rayDivDown(poolIndex));

        sideDelta.scaledDeltaPool = newScaledDeltaPool;

        if (borrow) emit Events.P2PBorrowDeltaUpdated(underlying, newScaledDeltaPool);
        else emit Events.P2PSupplyDeltaUpdated(underlying, newScaledDeltaPool);

        return (matchedDelta, amount - matchedDelta);
    }

    /// @notice Updates the delta and p2p amounts for a repay or withdraw after a promotion.
    /// @param toProcess The amount to repay/withdraw.
    /// @param inP2P The amount in p2p.
    /// @param p2pIndex The current p2p index.
    /// @param marketSideDelta The market side delta to update.
    /// @return The new amount in p2p.
    function _addToP2P(
        uint256 toProcess,
        uint256 inP2P,
        uint256 p2pIndex,
        Types.MarketSideDelta storage marketSideDelta
    ) internal returns (uint256) {
        if (toProcess == 0) return inP2P;

        uint256 toProcessP2P = toProcess.rayDivDown(p2pIndex);
        marketSideDelta.scaledTotalP2P += toProcessP2P;

        return inP2P + toProcessP2P;
    }

    /// @notice Calculates a new amount accounting for any fee required to be deducted by the delta.
    /// @param underlying The underlying address.
    /// @param amount The amount to repay/withdraw.
    /// @param indexes The current indexes.
    /// @return The new amount left to process.
    function _repayFee(address underlying, uint256 amount, Types.Indexes256 memory indexes)
        internal
        returns (uint256)
    {
        if (amount == 0) return 0;

        Types.Deltas storage deltas = _market[underlying].deltas;
        // Fee = (borrow.totalScaledP2P - borrow.delta) - (supply.totalScaledP2P - supply.delta).
        // No need to subtract borrow.delta as it is zero.
        uint256 feeToRepay = Math.zeroFloorSub(
            deltas.borrow.scaledTotalP2P.rayMul(indexes.borrow.p2pIndex),
            deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                deltas.supply.scaledDeltaPool.rayMul(indexes.supply.poolIndex)
            )
        );

        if (feeToRepay == 0) return amount;

        feeToRepay = Math.min(feeToRepay, amount);
        deltas.borrow.scaledTotalP2P =
            deltas.borrow.scaledTotalP2P.zeroFloorSub(feeToRepay.rayDivDown(indexes.borrow.p2pIndex));

        return amount - feeToRepay;
    }

    /// @notice Adds to idle supply if the supply cap is reached in a breaking repay, and returns a new toSupply amount.
    /// @param underlying The underlying address.
    /// @param amount The amount to repay. (by supplying on pool)
    /// @return toSupply The new amount to supply.
    function _handleSupplyCap(address underlying, uint256 amount) internal returns (uint256 toSupply) {
        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);
        uint256 supplyCap = config.getSupplyCap() * (10 ** config.getDecimals());
        if (supplyCap == 0) return amount;

        Types.Market storage market = _market[underlying];
        uint256 totalSupply = ERC20(market.aToken).totalSupply();
        if (totalSupply + amount > supplyCap) {
            toSupply = supplyCap - totalSupply;
            market.idleSupply += amount - toSupply;
        } else {
            toSupply = amount;
        }
    }

    /// @notice Withdraws idle supply.
    /// @param market The market storage.
    /// @param amount The amount to withdraw.
    /// @return The amount left to process.
    function _withdrawIdle(Types.Market storage market, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;

        uint256 idleSupply = market.idleSupply;
        if (idleSupply == 0) return amount;

        uint256 matchedIdle = Math.min(idleSupply, amount); // In underlying.
        market.idleSupply = idleSupply.zeroFloorSub(matchedIdle);

        return amount - matchedIdle;
    }

    /// @notice Borrows idle supply and returns an updated p2p balance.
    /// @param market The market storage.
    /// @param amount The amount to borrow.
    /// @param inP2P The user's amount in p2p.
    /// @param p2pBorrowIndex The current p2p borrow index.
    /// @return The amount left to process, and the updated p2p amount of the user.
    function _borrowIdle(Types.Market storage market, uint256 amount, uint256 inP2P, uint256 p2pBorrowIndex)
        internal
        returns (uint256, uint256)
    {
        uint256 idleSupply = market.idleSupply;
        if (idleSupply == 0) return (amount, inP2P);

        uint256 matchedIdle = Math.min(idleSupply, amount); // In underlying.
        market.idleSupply = idleSupply.zeroFloorSub(matchedIdle);

        return (amount - matchedIdle, inP2P + matchedIdle.rayDivDown(p2pBorrowIndex));
    }
}
