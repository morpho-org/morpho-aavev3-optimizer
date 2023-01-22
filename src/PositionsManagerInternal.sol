// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPriceOracleSentinel} from "@aave-v3-core/interfaces/IPriceOracleSentinel.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {DeltasLib} from "./libraries/DeltasLib.sol";
import {MarketSideDeltaLib} from "./libraries/MarketSideDeltaLib.sol";
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
    using DeltasLib for Types.Deltas;
    using MarketSideDeltaLib for Types.MarketSideDelta;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function _validatePermission(address delegator, address manager) internal view {
        if (!(delegator == manager || _isManaging[delegator][manager])) revert Errors.PermissionDenied();
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

    function _validateSupply(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.isSupplyPaused()) revert Errors.SupplyIsPaused();
    }

    function _validateSupplyCollateral(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.isSupplyCollateralPaused()) revert Errors.SupplyCollateralIsPaused();
    }

    function _validateBorrow(address underlying, uint256 amount, address borrower, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, borrower, receiver);
        if (market.isBorrowPaused()) revert Errors.BorrowIsPaused();

        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);
        if (!config.getBorrowingEnabled()) revert Errors.BorrowingNotEnabled();
        if (_E_MODE_CATEGORY_ID != 0 && _E_MODE_CATEGORY_ID != config.getEModeCategory()) {
            revert Errors.InconsistentEMode();
        }
    }

    function _authorizeBorrow(address underlying, uint256 amount, address borrower) internal view {
        Types.LiquidityData memory values = _liquidityData(underlying, borrower, 0, amount);
        if (values.debt > values.borrowable) revert Errors.UnauthorizedBorrow();
    }

    function _validateWithdraw(address underlying, uint256 amount, address supplier, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, supplier, receiver);
        if (market.isWithdrawPaused()) revert Errors.WithdrawIsPaused();
    }

    function _validateWithdrawCollateral(address underlying, uint256 amount, address supplier, address receiver)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateManagerInput(underlying, amount, supplier, receiver);
        if (market.isWithdrawCollateralPaused()) revert Errors.WithdrawCollateralIsPaused();
    }

    function _authorizeWithdrawCollateral(address underlying, uint256 amount, address supplier) internal view {
        if (_getUserHealthFactor(underlying, supplier, amount) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.UnauthorizedWithdraw();
        }
    }

    function _validateRepay(address underlying, uint256 amount, address user)
        internal
        view
        returns (Types.Market storage market)
    {
        market = _validateInput(underlying, amount, user);
        if (market.isRepayPaused()) revert Errors.RepayIsPaused();
    }

    function _authorizeLiquidate(address underlyingBorrowed, address underlyingCollateral, address borrower)
        internal
        view
        returns (uint256 closeFactor)
    {
        Types.Market storage borrowMarket = _market[underlyingBorrowed];
        Types.Market storage collateralMarket = _market[underlyingCollateral];

        if (!collateralMarket.isCreated() || !borrowMarket.isCreated()) revert Errors.MarketNotCreated();
        if (collateralMarket.isLiquidateCollateralPaused()) revert Errors.LiquidateCollateralIsPaused();
        if (borrowMarket.isLiquidateBorrowPaused()) revert Errors.LiquidateBorrowIsPaused();

        if (
            !_userCollaterals[borrower].contains(underlyingCollateral)
                || !_userBorrows[borrower].contains(underlyingBorrowed)
        ) {
            revert Errors.UserNotMemberOfMarket();
        }

        if (borrowMarket.isDeprecated()) {
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
        vars.onPool = marketBalances.scaledPoolSupplyBalance(user);
        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user);

        /// Peer-to-peer supply ///

        // Decrease the peer-to-peer borrow delta.
        (vars.toRepay, amount) = deltas.borrow.decrease(underlying, amount, indexes.borrow.poolIndex, true);

        // Promote pool borrowers.
        uint256 promoted;
        (promoted, amount,) = _promoteRoutine(underlying, amount, maxLoops, _promoteBorrowers);
        vars.toRepay += promoted;

        // Update the peer-to-peer totals.
        vars.inP2P = deltas.increaseP2P(underlying, promoted, vars.toRepay, indexes, true);

        /// Pool supply ///

        // Supply on pool.
        (vars.toSupply, vars.onPool) = _addToPool(amount, vars.onPool, indexes.supply.poolIndex);

        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P, false);
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
        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Peer-to-peer borrow ///

        // Decrease the peer-to-peer idle supply.
        (amount, vars.inP2P) = market.borrowIdle(underlying, amount, vars.inP2P, indexes.borrow.p2pIndex);

        // Decrease the peer-to-peer supply delta.
        (vars.toWithdraw, amount) = market.deltas.supply.decrease(underlying, amount, indexes.supply.poolIndex, false);

        // Promote pool suppliers.
        uint256 promoted;
        (promoted, amount,) = _promoteRoutine(underlying, amount, maxLoops, _promoteSuppliers);
        vars.toWithdraw += promoted;

        // Update the peer-to-peer totals.
        vars.inP2P += market.deltas.increaseP2P(underlying, promoted, vars.toWithdraw, indexes, false);

        /// Pool borrow ///

        // Borrow on pool.
        (vars.toBorrow, vars.onPool) = _addToPool(amount, vars.onPool, indexes.borrow.poolIndex);

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P, false);
    }

    function _executeRepay(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.SupplyRepayVars memory vars) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Pool repay ///

        // Repay borrow on pool.
        (vars.toRepay, amount, vars.onPool) = _subFromPool(amount, vars.onPool, indexes.borrow.poolIndex);

        // Repay borrow peer-to-peer.
        vars.inP2P = vars.inP2P.zeroFloorSub(amount.rayDivUp(indexes.borrow.p2pIndex)); // In peer-to-peer borrow unit.

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P, false);

        if (amount == 0) return vars;

        Types.Market storage market = _market[underlying];

        // Decrease the peer-to-peer borrow delta.
        uint256 toRepayStep;
        (toRepayStep, amount) = market.deltas.borrow.decrease(underlying, amount, indexes.borrow.poolIndex, true);
        vars.toRepay += toRepayStep;

        // Repay the fee.
        amount = market.deltas.repayFee(amount, indexes);

        /// Transfer repay ///

        // Promote pool borrowers.
        (toRepayStep, vars.toSupply, maxLoops) = _promoteRoutine(underlying, amount, maxLoops, _promoteBorrowers);
        vars.toRepay += toRepayStep;

        /// Breaking repay ///

        // Demote peer-to-peer suppliers.
        uint256 demoted = _demoteSuppliers(underlying, vars.toSupply, maxLoops);

        // Increase the peer-to-peer supply delta.
        market.deltas.supply.increase(underlying, vars.toSupply - demoted, indexes.supply, false);

        // Update the peer-to-peer totals.
        market.deltas.decreaseP2P(underlying, demoted, vars.toSupply, indexes, false);

        // Handle the supply cap.
        vars.toSupply = market.supplyIdle(underlying, vars.toSupply, _POOL.getConfiguration(underlying));
    }

    function _executeWithdraw(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.BorrowWithdrawVars memory vars) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        vars.onPool = marketBalances.scaledPoolSupplyBalance(user);
        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user);

        /// Pool withdraw ///

        // Withdraw supply on pool.
        (vars.toWithdraw, amount, vars.onPool) = _subFromPool(amount, vars.onPool, indexes.supply.poolIndex);

        Types.Market storage market = _market[underlying];

        // Withdraw idle supply.
        amount = market.withdrawIdle(underlying, amount);

        // Withdraw supply peer-to-peer.
        vars.inP2P = vars.inP2P.zeroFloorSub(amount.rayDivUp(indexes.supply.p2pIndex)); // In peer-to-peer supply unit.

        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P, false);

        if (amount == 0) return vars;

        // Decrease the peer-to-peer supply delta.
        uint256 toWithdrawStep;
        (toWithdrawStep, amount) = market.deltas.supply.decrease(underlying, amount, indexes.supply.poolIndex, false);
        vars.toWithdraw += toWithdrawStep;

        /// Transfer withdraw ///

        // Promote pool suppliers.
        (toWithdrawStep, vars.toBorrow, maxLoops) = _promoteRoutine(underlying, amount, maxLoops, _promoteSuppliers);
        vars.toWithdraw += toWithdrawStep;

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        uint256 demoted = _demoteBorrowers(underlying, vars.toBorrow, maxLoops);

        // Increase the peer-to-peer borrow delta.
        market.deltas.borrow.increase(underlying, vars.toBorrow - demoted, indexes.borrow, true);

        // Update the peer-to-peer totals.
        market.deltas.decreaseP2P(underlying, demoted, vars.toBorrow, indexes, true);
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
    ///         the amount left to process, and the number of loops left.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param maxLoops The maximum number of loops to run.
    /// @param promote The promote function.
    /// @return The amount to repay/withdraw from promote, the amount left to process, and the number of loops left.
    function _promoteRoutine(
        address underlying,
        uint256 amount,
        uint256 maxLoops,
        function(address, uint256, uint256) returns (uint256, uint256) promote
    ) internal returns (uint256, uint256, uint256) {
        if (amount == 0 || _market[underlying].isP2PDisabled()) {
            return (0, amount, maxLoops);
        }

        (uint256 promoted, uint256 loopsDone) = promote(underlying, amount, maxLoops); // In underlying.

        return (promoted, amount - promoted, maxLoops - loopsDone);
    }
}
