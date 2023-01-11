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

    function _validateSupply(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
        if (!market.pauseStatuses.isSupplyPaused) revert Errors.SupplyIsPaused();
    }

    function _validateSupplyCollateral(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
        if (!market.pauseStatuses.isSupplyCollateralPaused) revert Errors.SupplyCollateralIsPaused();
    }

    function _validateBorrow(address underlying, uint256 amount, address borrower) internal view {
        _validatePermission(borrower, msg.sender);

        Types.Market storage market = _validateInput(underlying, amount, borrower);
        if (market.pauseStatuses.isBorrowPaused) revert Errors.BorrowIsPaused();
        if (!_POOL.getConfiguration(underlying).getBorrowingEnabled()) revert Errors.BorrowingNotEnabled();

        uint256 eMode = _POOL.getUserEMode(address(this));
        if (eMode != 0) {
            if (eMode != _POOL.getConfiguration(address(this)).getEModeCategory()) revert Errors.InconsistentEMode();
        }

        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // In response, Morpho mirrors this behavior.
        address priceOracleSentinel = _ADDRESSES_PROVIDER.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            revert Errors.PriceOracleSentinelBorrowDisabled();
        }

        Types.LiquidityData memory values = _liquidityData(underlying, borrower, 0, amount);
        if (values.debt > values.borrowable) revert Errors.UnauthorisedBorrow();
    }

    function _validateRepay(address underlying, uint256 amount, address user) internal view {
        Types.Market storage market = _validateInput(underlying, amount, user);
        if (market.pauseStatuses.isRepayPaused) revert Errors.RepayIsPaused();
    }

    function _validateWithdraw(address underlying, uint256 amount, address supplier, address receiver) internal view {
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

    function _validateWithdrawCollateral(address underlying, uint256 amount, address supplier, address receiver)
        internal
        view
    {
        _validatePermission(supplier, msg.sender);

        Types.Market storage market = _validateInput(underlying, amount, receiver);
        if (market.pauseStatuses.isWithdrawCollateralPaused) revert Errors.WithdrawCollateralIsPaused();

        if (_getUserHealthFactor(underlying, supplier, amount) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.WithdrawUnauthorized();
        }
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
                revert Errors.UnauthorisedLiquidate();
            } else if (healthFactor >= Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
                revert Errors.UnauthorisedLiquidate();
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
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toRepay, uint256 toSupply) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        onPool = marketBalances.scaledPoolSupplyBalance(user);
        inP2P = marketBalances.scaledP2PSupplyBalance(user);

        _userCollaterals[user].add(underlying);

        /// Peer-to-peer supply ///

        // Match the peer-to-peer borrow delta.
        if (deltas.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pBorrowDelta.rayMul(indexes.borrow.poolIndex), amount); // In underlying.

            deltas.p2pBorrowDelta = deltas.p2pBorrowDelta.zeroFloorSub(amount.rayDiv(indexes.borrow.poolIndex));
            toRepay = matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PBorrowDeltaUpdated(underlying, deltas.p2pBorrowDelta);
        }

        // Promote pool borrowers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolBorrowers.getHead() != address(0)) {
            (uint256 promoted,) = _promoteBorrowers(underlying, amount, maxLoops); // In underlying.

            toRepay += promoted;
            amount -= promoted;
            deltas.p2pBorrowAmount += promoted.rayDiv(indexes.borrow.poolIndex);
        }

        if (toRepay > 0) {
            uint256 suppliedP2P = toRepay.rayDiv(indexes.borrow.p2pIndex);

            deltas.p2pSupplyAmount += suppliedP2P;
            inP2P += suppliedP2P;

            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Pool supply ///

        // Supply on pool.
        if (amount > 0) {
            onPool += amount.rayDiv(indexes.supply.poolIndex); // In scaled balance.
            toSupply = amount;
        }

        _updateSupplierInDS(underlying, user, onPool, inP2P);
    }

    function _executeBorrow(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.OutPositionVars memory vars) {
        Types.Market storage market = _market[underlying];
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Deltas storage deltas = market.deltas;

        _userBorrows[user].add(underlying);
        vars.onPool = marketBalances.scaledPoolBorrowBalance(user);
        vars.inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Peer-to-peer borrow ///

        // Match the peer-to-peer supply delta.
        if (deltas.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pSupplyDelta.rayMul(indexes.supply.poolIndex), amount); // In underlying.

            deltas.p2pSupplyDelta = deltas.p2pSupplyDelta.zeroFloorSub(amount.rayDiv(indexes.supply.poolIndex));
            vars.toWithdraw = matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PSupplyDeltaUpdated(underlying, deltas.p2pSupplyDelta);
        }

        // Promote pool suppliers.
        if (
            amount > 0 && !market.pauseStatuses.isP2PDisabled
                && _marketBalances[underlying].poolSuppliers.getHead() != address(0)
        ) {
            (uint256 promoted,) = _promoteSuppliers(underlying, amount, maxLoops); // In underlying.

            vars.toWithdraw += promoted;
            amount -= promoted;
            deltas.p2pSupplyAmount += promoted.rayDiv(indexes.supply.p2pIndex);
        }

        if (vars.toWithdraw > 0) {
            uint256 borrowedP2P = vars.toWithdraw.rayDiv(indexes.borrow.p2pIndex); // In peer-to-peer unit.

            deltas.p2pBorrowAmount += borrowedP2P;
            vars.inP2P += borrowedP2P;
            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Pool borrow ///

        // Borrow on pool.
        if (amount > 0) {
            vars.onPool += amount.rayDiv(indexes.borrow.poolIndex); // In adUnit.
            vars.toBorrow = amount;
        }

        _updateBorrowerInDS(underlying, user, vars.onPool, vars.inP2P);
    }

    function _executeRepay(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toSupply, uint256 toRepay) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Market storage market = _market[underlying];
        Types.Deltas storage deltas = market.deltas;

        onPool = marketBalances.scaledPoolBorrowBalance(user);
        inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Pool repay ///

        // Repay borrow on pool.
        if (onPool > 0) {
            toRepay = Math.min(onPool.rayMul(indexes.borrow.poolIndex), amount);
            amount -= toRepay;
            onPool -= Math.min(onPool, toRepay.rayDiv(indexes.borrow.poolIndex)); // In scaled balance.

            if (amount == 0) {
                _updateBorrowerInDS(underlying, user, onPool, inP2P);

                if (inP2P == 0 && onPool == 0) {
                    _userBorrows[user].remove(underlying);
                }

                return (onPool, inP2P, toSupply, toRepay);
            }
        }

        inP2P -= Math.min(inP2P, amount.rayDiv(indexes.borrow.p2pIndex)); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(underlying, user, onPool, inP2P);

        // Reduce the peer-to-peer borrow delta.
        if (amount > 0 && deltas.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pBorrowDelta.rayMul(indexes.borrow.poolIndex), amount); // In underlying.

            deltas.p2pBorrowDelta = deltas.p2pBorrowDelta.zeroFloorSub(amount.rayDiv(indexes.borrow.poolIndex));
            deltas.p2pBorrowAmount -= matchedDelta.rayDiv(indexes.borrow.p2pIndex);
            toRepay += matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PBorrowDeltaUpdated(underlying, deltas.p2pBorrowDelta);
            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        // Repay the fee.
        if (amount > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            uint256 feeToRepay = Math.zeroFloorSub(
                deltas.p2pBorrowAmount.rayMul(indexes.borrow.p2pIndex),
                deltas.p2pSupplyAmount.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                    deltas.p2pSupplyDelta.rayMul(indexes.supply.poolIndex)
                )
            );

            if (feeToRepay > 0) {
                feeToRepay = Math.min(feeToRepay, amount);
                amount -= feeToRepay;
                deltas.p2pBorrowAmount -= feeToRepay.rayDiv(indexes.borrow.p2pIndex);
                emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
            }
        }

        /// Transfer repay ///

        // Promote pool borrowers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolBorrowers.getHead() != address(0)) {
            (uint256 promoted, uint256 loopsDone) = _promoteBorrowers(underlying, amount, maxLoops);
            maxLoops -= loopsDone;
            amount -= promoted;
            toRepay += promoted;
        }

        /// Breaking repay ///

        // Demote peer-to-peer suppliers.
        if (amount > 0) {
            uint256 demoted = _demoteSuppliers(underlying, amount, maxLoops);

            // Increase the peer-to-peer supply delta.
            if (demoted < amount) {
                deltas.p2pSupplyDelta += (amount - demoted).rayDiv(indexes.supply.poolIndex);
                emit Events.P2PSupplyDeltaUpdated(underlying, deltas.p2pSupplyDelta);
            }

            // Math.min as the last decimal might flip.
            deltas.p2pSupplyAmount -= Math.min(demoted.rayDiv(indexes.supply.p2pIndex), deltas.p2pSupplyAmount);
            deltas.p2pBorrowAmount -= Math.min(amount.rayDiv(indexes.borrow.p2pIndex), deltas.p2pBorrowAmount);
            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);

            toSupply = amount;
        }

        if (inP2P == 0 && onPool == 0) _userBorrows[user].remove(underlying);
    }

    function _executeWithdraw(
        address underlying,
        uint256 amount,
        address user,
        uint256 maxLoops,
        Types.Indexes256 memory indexes
    ) internal returns (Types.OutPositionVars memory vars) {
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];
        Types.Market storage market = _market[underlying];
        Types.Deltas storage deltas = market.deltas;

        vars.onPool = marketBalances.scaledPoolSupplyBalance(user);
        vars.inP2P = marketBalances.scaledP2PSupplyBalance(user);

        /// Pool withdraw ///

        // Withdraw supply on pool.
        if (vars.onPool > 0) {
            vars.toWithdraw = Math.min(vars.onPool.rayMul(indexes.supply.poolIndex), amount);
            amount -= vars.toWithdraw;
            vars.onPool -= Math.min(vars.onPool, vars.toWithdraw.rayDiv(indexes.supply.poolIndex));

            if (amount == 0) {
                _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P);

                if (vars.inP2P == 0 && vars.onPool == 0) {
                    _userCollaterals[user].remove(underlying);
                }

                return vars;
            }
        }

        vars.inP2P -= Math.min(vars.inP2P, amount.rayDiv(indexes.supply.p2pIndex)); // In peer-to-peer supply unit.
        _updateSupplierInDS(underlying, user, vars.onPool, vars.inP2P);

        // Reduce the peer-to-peer supply delta.
        if (amount > 0 && deltas.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pSupplyDelta.rayMul(indexes.supply.poolIndex), amount); // In underlying.

            deltas.p2pSupplyDelta = deltas.p2pSupplyDelta.zeroFloorSub(amount.rayDiv(indexes.supply.poolIndex));
            deltas.p2pSupplyAmount -= matchedDelta.rayDiv(indexes.supply.p2pIndex);
            vars.toWithdraw += matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PSupplyDeltaUpdated(underlying, deltas.p2pSupplyDelta);
            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolSuppliers.getHead() != address(0)) {
            (uint256 promoted, uint256 loopsDone) = _promoteSuppliers(underlying, amount, maxLoops);
            maxLoops -= loopsDone;
            amount -= promoted;
            vars.toWithdraw += promoted;
        }

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        if (amount > 0) {
            uint256 demoted = _demoteBorrowers(underlying, amount, maxLoops);

            // Increase the peer-to-peer borrow delta.
            if (demoted < amount) {
                deltas.p2pBorrowDelta += (amount - demoted).rayDiv(indexes.borrow.poolIndex);
                emit Events.P2PBorrowDeltaUpdated(underlying, deltas.p2pBorrowDelta);
            }

            deltas.p2pSupplyAmount -= Math.min(deltas.p2pSupplyAmount, amount.rayDiv(indexes.supply.p2pIndex));
            deltas.p2pBorrowAmount -= Math.min(deltas.p2pBorrowAmount, demoted.rayDiv(indexes.borrow.p2pIndex));
            emit Events.P2PAmountsUpdated(underlying, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
            vars.toBorrow = amount;
        }

        if (vars.inP2P == 0 && vars.onPool == 0) _userCollaterals[user].remove(underlying);
    }

    function _calculateAmountToSeize(
        address underlyingBorrowed,
        address underlyingCollateral,
        uint256 maxToLiquidate,
        address borrower,
        Types.MarketSideIndexes256 memory collateralIndexes
    ) internal view returns (uint256 amountToLiquidate, uint256 amountToSeize) {
        amountToLiquidate = maxToLiquidate;
        (,, uint256 liquidationBonus, uint256 collateralTokenUnit,,) =
            _POOL.getConfiguration(underlyingCollateral).getParams();
        uint256 borrowTokenUnit = _POOL.getConfiguration(underlyingBorrowed).getDecimals();

        unchecked {
            collateralTokenUnit = 10 ** collateralTokenUnit;
            borrowTokenUnit = 10 ** borrowTokenUnit;
        }

        IPriceOracleGetter oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
        uint256 borrowPrice = oracle.getAssetPrice(underlyingBorrowed);
        uint256 collateralPrice = oracle.getAssetPrice(underlyingCollateral);

        amountToSeize = ((amountToLiquidate * borrowPrice * collateralTokenUnit) / (borrowTokenUnit * collateralPrice))
            .percentMul(liquidationBonus);

        uint256 collateralBalance = _getUserSupplyBalanceFromIndexes(underlyingCollateral, borrower, collateralIndexes);

        if (amountToSeize > collateralBalance) {
            amountToSeize = collateralBalance;
            amountToLiquidate = (
                (collateralBalance * collateralPrice * borrowTokenUnit) / (borrowPrice * collateralTokenUnit)
            ).percentDiv(liquidationBonus);
        }
    }
}
