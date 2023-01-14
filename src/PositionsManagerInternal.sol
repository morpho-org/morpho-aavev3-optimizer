// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {DataTypes} from "./libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";
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
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

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

    function _validatePermission(address owner, address manager) internal view {
        if (!(owner == manager || _isManaging[owner][manager])) revert Errors.PermissionDenied();
    }

    function _validateSupplyInput(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
        if (!market.pauseStatuses.isSupplyPaused) revert Errors.SupplyIsPaused();
    }

    function _validateSupplyCollateralInput(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
        if (!market.pauseStatuses.isSupplyCollateralPaused) revert Errors.SupplyCollateralIsPaused();
    }

    function _validateBorrowInput(address underlying, uint256 amount, address borrower) internal view {
        _validatePermission(borrower, msg.sender);

        Types.Market storage market = _validateInput(underlying, amount, borrower);
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
    {
        _validatePermission(supplier, msg.sender);

        Types.Market storage market = _validateInput(underlying, amount, receiver);
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
    {
        _validatePermission(supplier, msg.sender);

        Types.Market storage market = _validateInput(underlying, amount, receiver);
        if (market.pauseStatuses.isWithdrawCollateralPaused) revert Errors.WithdrawCollateralIsPaused();
    }

    function _validateWithdrawCollateral(address underlying, uint256 amount, address supplier) internal view {
        if (_getUserHealthFactor(underlying, supplier, amount) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.UnauthorizedWithdraw();
        }
    }

    function _validateRepayInput(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
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
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = _market[underlying].deltas;

        vars.onPool = marketBalances.scaledPoolSupplyBalance(user);
        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user);

        (vars.toRepay, amount) = _matchDelta(underlying, amount, indexes.borrow.poolIndex, true);
        uint256 toRepayFromPromote;
        (toRepayFromPromote, amount,) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.borrow.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteBorrowers
            }),
            _marketBalances[underlying].poolBorrowers,
            deltas.borrow
        );
        vars.toRepay += toRepayFromPromote;
        deltas.borrow.amount += toRepayFromPromote;
        vars.inP2P =
            _updateDeltaP2PAmounts(underlying, vars.toRepay, indexes.supply.p2pIndex, vars.inP2P, deltas.supply);
        (vars.toSupply, vars.onPool) = _processPoolAmountAddition(amount, vars.onPool, indexes.supply.poolIndex);
        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P);
    }

    function _executeBorrow(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.WithdrawBorrowVars memory vars) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        (amount, vars.inP2P) = _borrowIdle(market, amount, vars.inP2P, indexes.borrow.p2pIndex);
        (vars.toWithdraw, amount) = _matchDelta(underlying, amount, indexes.supply.poolIndex, false);
        uint256 toWithdrawFromPromote;
        (toWithdrawFromPromote, amount,) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.supply.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteSuppliers
            }),
            _marketBalances[underlying].poolSuppliers,
            deltas.supply
        );
        vars.toWithdraw += toWithdrawFromPromote;
        deltas.supply.amount += toWithdrawFromPromote;
        vars.inP2P =
            _updateDeltaP2PAmounts(underlying, vars.toWithdraw, indexes.borrow.p2pIndex, vars.inP2P, deltas.borrow);
        (vars.toBorrow, vars.onPool) = _processPoolAmountAddition(amount, vars.onPool, indexes.borrow.poolIndex);

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P);
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

        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        (vars.toRepay, amount, vars.onPool) =
            _processPoolAmountSubtraction(amount, vars.onPool, indexes.borrow.poolIndex);
        if (amount == 0) {
            _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P);
            return vars;
        }

        vars.inP2P -= Math.min(vars.inP2P, amount.rayDiv(indexes.borrow.p2pIndex)); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P);

        (vars.toRepay, amount) = _matchDelta(underlying, amount, indexes.borrow.poolIndex, true);
        deltas.borrow.amount -= vars.toRepay.rayDiv(indexes.borrow.p2pIndex);
        emit Events.P2PAmountsUpdated(underlying, deltas.supply.amount, deltas.borrow.amount);

        amount = _repayFee(underlying, amount, indexes);

        uint256 toRepayFromPromote;
        (toRepayFromPromote, amount, maxLoops) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.borrow.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteBorrowers
            }),
            _marketBalances[underlying].poolBorrowers,
            _market[underlying].deltas.borrow
        );
        vars.toRepay += toRepayFromPromote;

        vars.toSupply = _demoteRoutine(underlying, amount, maxLoops, indexes, _demoteSuppliers, deltas, false);
        vars.toSupply = _handleSupplyCap(underlying, vars.toSupply);
    }

    function _executeWithdraw(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.WithdrawBorrowVars memory vars) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        vars.onPool = marketBalances.scaledPoolSupplyBalance(user);
        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user);

        (vars.toWithdraw, amount, vars.onPool) =
            _processPoolAmountSubtraction(amount, vars.onPool, indexes.supply.poolIndex);
        if (amount == 0) {
            _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P);
            return vars;
        }
        vars.inP2P -= Math.min(vars.inP2P, amount.rayDiv(indexes.supply.p2pIndex)); // In peer-to-peer supply unit.

        _withdrawIdle(market, amount, vars.inP2P, indexes.supply.p2pIndex);
        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P);

        (vars.toWithdraw, amount) = _matchDelta(underlying, amount, indexes.supply.poolIndex, false);
        deltas.supply.amount -= vars.toWithdraw.rayDiv(indexes.supply.p2pIndex);
        emit Events.P2PAmountsUpdated(underlying, deltas.supply.amount, deltas.borrow.amount);

        uint256 toWithdrawFromPromote;
        (toWithdrawFromPromote, amount, maxLoops) = _promoteRoutine(
            Types.PromoteVars({
                underlying: underlying,
                amount: amount,
                poolIndex: indexes.supply.poolIndex,
                maxLoops: maxLoops,
                promote: _promoteSuppliers
            }),
            _marketBalances[underlying].poolSuppliers,
            _market[underlying].deltas.supply
        );
        vars.toWithdraw += toWithdrawFromPromote;

        vars.toBorrow = _demoteRoutine(underlying, amount, maxLoops, indexes, _demoteBorrowers, deltas, true);
    }

    function _processPoolAmountAddition(uint256 amount, uint256 onPool, uint256 poolIndex)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 toProcess;
        if (amount > 0) {
            onPool += amount.rayDiv(poolIndex); // In scaled balance.
            toProcess = amount;
        }
        return (toProcess, onPool);
    }

    function _processPoolAmountSubtraction(uint256 amount, uint256 onPool, uint256 poolIndex)
        internal
        pure
        returns (uint256, uint256, uint256)
    {
        uint256 toProcess;
        if (onPool > 0) {
            toProcess = Math.min(onPool.rayMul(poolIndex), amount);
            amount -= toProcess;
            onPool -= Math.min(onPool, toProcess.rayDiv(poolIndex)); // In scaled balance.
        }
        return (toProcess, amount, onPool);
    }

    function _promoteRoutine(
        Types.PromoteVars memory vars,
        ThreeHeapOrdering.HeapArray storage heap,
        Types.MarketSideDelta storage promoteSideDelta
    ) internal returns (uint256, uint256, uint256) {
        uint256 toProcess;
        if (vars.amount > 0 && !_market[vars.underlying].pauseStatuses.isP2PDisabled && heap.getHead() != address(0)) {
            (uint256 promoted, uint256 loopsDone) = vars.promote(vars.underlying, vars.amount, vars.maxLoops); // In underlying.

            toProcess = promoted;
            vars.amount -= promoted;
            promoteSideDelta.amount += promoted.rayDiv(vars.poolIndex);
            vars.maxLoops -= loopsDone;
        }
        return (toProcess, vars.amount, vars.maxLoops);
    }

    function _demoteRoutine(
        address underlying,
        uint256 amount,
        uint256 maxLoops,
        Types.Indexes256 memory indexes,
        function(address, uint256, uint256) returns (uint256) demote,
        Types.Deltas storage deltas,
        bool borrow
    ) internal returns (uint256 toProcess) {
        Types.MarketSideIndexes256 memory demotedIndexes = borrow ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrow ? indexes.supply : indexes.borrow;
        Types.MarketSideDelta storage demotedDelta = borrow ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrow ? deltas.supply : deltas.borrow;

        if (amount > 0) {
            uint256 demoted = demote(underlying, amount, maxLoops);

            // Increase the peer-to-peer supply delta.
            if (demoted < amount) {
                demotedDelta.delta += (amount - demoted).rayDiv(demotedIndexes.poolIndex);
                if (borrow) emit Events.P2PBorrowDeltaUpdated(underlying, demotedDelta.delta);
                else emit Events.P2PSupplyDeltaUpdated(underlying, demotedDelta.delta);
            }

            // Math.min as the last decimal might flip.
            demotedDelta.amount -= Math.min(demoted.rayDiv(demotedIndexes.p2pIndex), demotedDelta.amount);
            counterDelta.amount -= Math.min(amount.rayDiv(counterIndexes.p2pIndex), counterDelta.amount);
            emit Events.P2PAmountsUpdated(underlying, deltas.supply.amount, deltas.borrow.amount);

            toProcess = amount;
        }
    }

    function _matchDelta(address underlying, uint256 amount, uint256 poolIndex, bool borrow)
        internal
        returns (uint256, uint256)
    {
        Types.MarketSideDelta storage sideDelta =
            borrow ? _market[underlying].deltas.borrow : _market[underlying].deltas.supply;
        uint256 toProcess;

        if (sideDelta.delta > 0) {
            uint256 matchedDelta = Math.min(sideDelta.delta.rayMul(poolIndex), amount); // In underlying.

            sideDelta.delta = sideDelta.delta.zeroFloorSub(amount.rayDiv(poolIndex));
            toProcess = matchedDelta;
            amount -= matchedDelta;
            if (borrow) emit Events.P2PBorrowDeltaUpdated(underlying, sideDelta.delta);
            else emit Events.P2PSupplyDeltaUpdated(underlying, sideDelta.delta);
        }
        return (toProcess, amount);
    }

    function _updateDeltaP2PAmounts(
        address underlying,
        uint256 toRepayOrWithdraw,
        uint256 p2pIndex,
        uint256 inP2P,
        Types.MarketSideDelta storage delta
    ) internal returns (uint256) {
        Types.Deltas storage deltas = _market[underlying].deltas;
        if (toRepayOrWithdraw > 0) {
            uint256 toProcessP2P = toRepayOrWithdraw.rayDiv(p2pIndex);

            delta.amount += toProcessP2P;
            inP2P += toProcessP2P;

            emit Events.P2PAmountsUpdated(underlying, deltas.supply.amount, deltas.borrow.amount);
        }
        return inP2P;
    }

    function _repayFee(address underlying, uint256 amount, Types.Indexes256 memory indexes)
        internal
        returns (uint256)
    {
        Types.Deltas storage deltas = _market[underlying].deltas;
        // Repay the fee.
        if (amount > 0) {
            // Fee = (borrow.amount - borrow.delta) - (supply.amount - supply.delta).
            // No need to subtract borrow.delta as it is zero.
            uint256 feeToRepay = Math.zeroFloorSub(
                deltas.borrow.amount.rayMul(indexes.borrow.p2pIndex),
                deltas.supply.amount.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                    deltas.supply.delta.rayMul(indexes.supply.poolIndex)
                )
            );

            if (feeToRepay > 0) {
                feeToRepay = Math.min(feeToRepay, amount);
                amount -= feeToRepay;
                deltas.borrow.amount -= feeToRepay.rayDiv(indexes.borrow.p2pIndex);
                emit Events.P2PAmountsUpdated(underlying, deltas.supply.amount, deltas.borrow.amount);
            }
        }
        return amount;
    }

    function _handleSupplyCap(address underlying, uint256 amount) internal returns (uint256 toSupply) {
        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);
        uint256 supplyCap = config.getSupplyCap() * (10 ** config.getDecimals());
        if (supplyCap == 0) return amount;

        uint256 totalSupply = ERC20(_market[underlying].aToken).totalSupply();
        if (totalSupply + amount > supplyCap) {
            toSupply = supplyCap - totalSupply;
            _market[underlying].idleSupply += amount - toSupply;
        } else {
            toSupply = amount;
        }
    }

    function _withdrawIdle(Types.Market storage market, uint256 amount, uint256 inP2P, uint256 p2pSupplyIndex)
        internal
    {
        if (amount > 0 && market.idleSupply > 0 && inP2P > 0) {
            uint256 matchedIdle = Math.min(Math.min(market.idleSupply, amount), inP2P.rayMul(p2pSupplyIndex));
            market.idleSupply -= matchedIdle;
        }
    }

    function _borrowIdle(Types.Market storage market, uint256 amount, uint256 inP2P, uint256 p2pBorrowIndex)
        internal
        returns (uint256, uint256)
    {
        uint256 idleSupply = market.idleSupply;
        if (idleSupply > 0) {
            uint256 matchedIdle = Math.min(idleSupply, amount); // In underlying.
            market.idleSupply -= matchedIdle;
            amount -= matchedIdle;
            inP2P += matchedIdle.rayDiv(p2pBorrowIndex);
        }
        return (amount, inP2P);
    }
}
