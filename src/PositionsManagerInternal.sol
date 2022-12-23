// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./libraries/Types.sol";
import {Constants} from "./libraries/Constants.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {MarketMaskLib} from "./libraries/MarketMaskLib.sol";

import {DataTypes} from "./libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";

import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {IPriceOracleSentinel} from "./interfaces/Interfaces.sol";

import {MatchingEngine} from "./MatchingEngine.sol";

abstract contract PositionsManagerInternal is MatchingEngine {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using MarketBalanceLib for Types.MarketBalances;
    using MarketLib for Types.Market;
    using MarketMaskLib for Types.UserMarkets;
    using WadRayMath for uint256;
    using Math for uint256;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    function _validateSupply(address poolToken, address user, uint256 amount) internal view {
        Types.Market storage market = _market[poolToken];
        if (user == address(0)) revert Errors.AddressIsZero();
        if (amount == 0) revert Errors.AmountIsZero();

        if (!market.isCreated()) revert Errors.MarketNotCreated();
        if (market.pauseStatuses.isSupplyPaused) revert Errors.SupplyIsPaused();
    }

    function _executeSupply(
        address poolToken,
        address user,
        uint256 amount,
        Types.IndexesMem memory indexes,
        uint256 maxLoops
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toSupply, uint256 toRepay) {
        Types.Market storage market = _market[poolToken];
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Delta storage deltas = market.deltas;
        onPool = marketBalances.scaledPoolSupplyBalance(user);
        inP2P = marketBalances.scaledP2PSupplyBalance(user);

        _userMarkets[user].setSupplying(market.borrowMask, true);

        /// Peer-to-peer supply ///

        // Match the peer-to-peer borrow delta.
        if (deltas.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pBorrowDelta.rayMul(indexes.poolBorrowIndex), amount); // In underlying.

            deltas.p2pBorrowDelta = deltas.p2pBorrowDelta.zeroFloorSub(amount.rayDiv(indexes.poolBorrowIndex));
            toRepay = matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PBorrowDeltaUpdated(poolToken, deltas.p2pBorrowDelta);
        }

        // Promote pool borrowers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolBorrowers.getHead() != address(0)) {
            (uint256 matched,) = _matchBorrowers(poolToken, amount, maxLoops); // In underlying.

            toRepay += matched;
            amount -= matched;
            deltas.p2pBorrowAmount += matched.rayDiv(indexes.poolBorrowIndex);
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.rayDiv(indexes.p2pBorrowIndex);

            deltas.p2pSupplyAmount += toAddInP2P;
            inP2P += toAddInP2P;

            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Pool supply ///

        // Supply on pool.
        if (amount > 0) {
            onPool += amount.rayDiv(indexes.poolSupplyIndex); // In scaled balance.
            toSupply = amount;
        }
        _updateSupplierInDS(poolToken, user, onPool, inP2P);
    }

    function _validateBorrow(address poolToken, address user, uint256 amount) internal view {
        Types.Market storage market = _market[poolToken];

        if (amount == 0) revert Errors.AmountIsZero();
        if (!market.isCreated()) revert Errors.MarketNotCreated();
        if (market.pauseStatuses.isBorrowPaused) revert Errors.BorrowIsPaused();
        if (!_pool.getConfiguration(market.underlying).getBorrowingEnabled()) {
            revert Errors.BorrowingNotEnabled();
        }
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // In response, Morpho mirrors this behavior.
        address priceOracleSentinel = _addressesProvider.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            revert Errors.PriceOracleSentinelBorrowDisabled();
        }

        Types.LiquidityData memory values = _liquidityData(poolToken, user, 0, amount);
        if (values.debt > values.maxDebt) revert Errors.UnauthorisedBorrow();
    }

    function _executeBorrow(
        address poolToken,
        address user,
        uint256 amount,
        Types.IndexesMem memory indexes,
        uint256 maxLoops
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) {
        Types.Market storage market = _market[poolToken];
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Delta storage deltas = market.deltas;

        _userMarkets[user].setBorrowing(market.borrowMask, true);
        onPool = marketBalances.scaledPoolBorrowBalance(user);
        inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Peer-to-peer borrow ///

        // Match the peer-to-peer supply delta.
        if (deltas.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex), amount); // In underlying.

            deltas.p2pSupplyDelta = deltas.p2pSupplyDelta.zeroFloorSub(amount.rayDiv(indexes.poolSupplyIndex));
            toWithdraw += matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PSupplyDeltaUpdated(poolToken, deltas.p2pSupplyDelta);
        }

        // Promote pool suppliers.
        if (
            amount > 0 && !market.pauseStatuses.isP2PDisabled
                && _marketBalances[poolToken].poolSuppliers.getHead() != address(0)
        ) {
            (uint256 matched,) = _matchSuppliers(poolToken, amount, maxLoops); // In underlying.

            toWithdraw += matched;
            amount -= matched;
            deltas.p2pSupplyAmount += matched.rayDiv(indexes.p2pSupplyIndex);
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.rayDiv(indexes.p2pBorrowIndex); // In peer-to-peer unit.

            deltas.p2pBorrowAmount += toAddInP2P;
            inP2P += toAddInP2P;
            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Pool borrow ///

        // Borrow on pool.
        if (amount > 0) {
            onPool += amount.rayDiv(indexes.poolBorrowIndex); // In adUnit.
            toBorrow = amount;
        }
        _updateBorrowerInDS(poolToken, msg.sender, onPool, inP2P);
    }

    function _validateRepay(address poolToken, uint256 amount) internal view {
        if (amount == 0) revert Errors.AmountIsZero();
        Types.Market storage market = _market[poolToken];
        if (!market.isCreated()) revert Errors.MarketNotCreated();
        if (market.pauseStatuses.isRepayPaused) revert Errors.RepayIsPaused();
    }

    function _executeRepay(
        address poolToken,
        address user,
        uint256 amount,
        Types.IndexesMem memory indexes,
        uint256 maxLoops
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toSupply, uint256 toRepay) {
        Types.Market storage market = _market[poolToken];
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Delta storage deltas = market.deltas;

        onPool = marketBalances.scaledPoolBorrowBalance(user);
        inP2P = marketBalances.scaledP2PBorrowBalance(user);

        /// Pool repay ///

        // Repay borrow on pool.
        if (onPool > 0) {
            toRepay = Math.min(onPool.rayMul(indexes.poolBorrowIndex), amount);
            amount -= toRepay;

            onPool -= Math.min(onPool, toRepay.rayDiv(indexes.poolBorrowIndex)); // In adUnit.

            if (amount == 0) {
                _updateBorrowerInDS(poolToken, user, onPool, inP2P);

                if (inP2P == 0 && onPool == 0) {
                    _userMarkets[user].setBorrowing(market.borrowMask, false);
                }

                return (onPool, inP2P, toSupply, toRepay);
            }
        }

        inP2P -= Math.min(inP2P, amount.rayDiv(indexes.p2pBorrowIndex)); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(poolToken, user, onPool, inP2P);

        // Reduce the peer-to-peer borrow delta.
        if (amount > 0 && deltas.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pBorrowDelta.rayMul(indexes.poolBorrowIndex), amount); // In underlying.

            deltas.p2pBorrowDelta = deltas.p2pBorrowDelta.zeroFloorSub(amount.rayDiv(indexes.poolBorrowIndex));
            deltas.p2pBorrowAmount -= matchedDelta.rayDiv(indexes.p2pBorrowIndex);
            toRepay += matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PBorrowDeltaUpdated(poolToken, deltas.p2pBorrowDelta);
            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        // Repay the fee.
        if (amount > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            uint256 feeToRepay = Math.zeroFloorSub(
                deltas.p2pBorrowAmount.rayMul(indexes.p2pBorrowIndex),
                deltas.p2pSupplyAmount.rayMul(indexes.p2pSupplyIndex).zeroFloorSub(
                    deltas.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex)
                )
            );

            if (feeToRepay > 0) {
                feeToRepay = Math.min(feeToRepay, amount);
                amount -= feeToRepay;
                deltas.p2pBorrowAmount -= feeToRepay.rayDiv(indexes.p2pBorrowIndex);
                emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
            }
        }

        /// Transfer repay ///

        // Promote pool borrowers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolBorrowers.getHead() != address(0)) {
            (uint256 matched, uint256 loopsDone) = _matchBorrowers(poolToken, amount, maxLoops);
            maxLoops = maxLoops.zeroFloorSub(loopsDone);

            amount -= matched;
            toRepay += matched;
        }

        /// Breaking repay ///

        // Demote peer-to-peer suppliers.
        if (amount > 0) {
            uint256 unmatched = _unmatchSuppliers(poolToken, amount, maxLoops);

            // Increase the peer-to-peer supply delta.
            if (unmatched < amount) {
                deltas.p2pSupplyDelta += (amount - unmatched).rayDiv(indexes.poolSupplyIndex);
                emit Events.P2PSupplyDeltaUpdated(poolToken, deltas.p2pSupplyDelta);
            }

            // Math.min as the last decimal might flip.
            deltas.p2pSupplyAmount -= Math.min(unmatched.rayDiv(indexes.p2pSupplyIndex), deltas.p2pSupplyAmount);
            deltas.p2pBorrowAmount -= Math.min(amount.rayDiv(indexes.p2pBorrowIndex), deltas.p2pBorrowAmount);
            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);

            toSupply = amount;
        }

        if (inP2P == 0 && onPool == 0) _userMarkets[user].setBorrowing(market.borrowMask, false);
    }

    function _validateWithdraw(address poolToken, address supplier, address receiver, uint256 amount) internal view {
        Types.Market storage market = _market[poolToken];
        if (amount == 0) revert Errors.AmountIsZero();
        if (receiver == address(0)) revert Errors.AddressIsZero();
        if (!market.isCreated()) revert Errors.MarketNotCreated();
        if (market.pauseStatuses.isWithdrawPaused) revert Errors.WithdrawIsPaused();
        // Aave can enable an oracle sentinel in specific circumstances which can prevent users to borrow.
        // For safety concerns and as a withdraw on Morpho can trigger a borrow on pool, Morpho prevents withdrawals in such circumstances.
        address priceOracleSentinel = _addressesProvider.getPriceOracleSentinel();
        if (priceOracleSentinel != address(0) && !IPriceOracleSentinel(priceOracleSentinel).isBorrowAllowed()) {
            revert Errors.PriceOracleSentinelBorrowPaused();
        }
        if (_getUserHealthFactor(supplier, poolToken, amount) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.WithdrawUnauthorized();
        }
    }

    function _executeWithdraw(
        address poolToken,
        address user,
        uint256 amount,
        Types.IndexesMem memory indexes,
        uint256 maxLoops
    ) internal returns (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) {
        Types.Market storage market = _market[poolToken];
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];
        Types.Delta storage deltas = market.deltas;

        onPool = marketBalances.scaledPoolSupplyBalance(user);
        inP2P = marketBalances.scaledP2PSupplyBalance(user);

        /// Pool withdraw ///

        // Withdraw supply on pool.
        if (onPool > 0) {
            toWithdraw = Math.min(onPool.rayMul(indexes.poolSupplyIndex), amount);
            amount -= toWithdraw;
            onPool -= Math.min(onPool, toWithdraw.rayDiv(indexes.poolSupplyIndex));

            if (amount == 0) {
                _updateSupplierInDS(poolToken, user, onPool, inP2P);

                if (inP2P == 0 && onPool == 0) {
                    _userMarkets[user].setSupplying(market.borrowMask, false);
                }

                return (onPool, inP2P, toBorrow, toWithdraw);
            }
        }

        inP2P -= Math.min(inP2P, amount.rayDiv(indexes.p2pSupplyIndex)); // In peer-to-peer supply unit.
        _updateSupplierInDS(poolToken, user, onPool, inP2P);

        // Reduce the peer-to-peer supply delta.
        if (amount > 0 && deltas.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(deltas.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex), amount); // In underlying.

            deltas.p2pSupplyDelta = deltas.p2pSupplyDelta.zeroFloorSub(amount.rayDiv(indexes.poolSupplyIndex));
            deltas.p2pSupplyAmount -= matchedDelta.rayDiv(indexes.p2pSupplyIndex);
            toWithdraw += matchedDelta;
            amount -= matchedDelta;
            emit Events.P2PSupplyDeltaUpdated(poolToken, deltas.p2pSupplyDelta);
            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (amount > 0 && !market.pauseStatuses.isP2PDisabled && marketBalances.poolSuppliers.getHead() != address(0)) {
            (uint256 matched, uint256 loopsDone) = _matchSuppliers(poolToken, amount, maxLoops);
            if (maxLoops <= loopsDone) {
                maxLoops = 0;
            } else {
                maxLoops -= loopsDone;
            }

            amount -= matched;
            toWithdraw += matched;
        }

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        if (amount > 0) {
            uint256 unmatched = _unmatchBorrowers(poolToken, amount, maxLoops);

            // Increase the peer-to-peer borrow delta.
            if (unmatched < amount) {
                deltas.p2pBorrowDelta += (amount - unmatched).rayDiv(indexes.poolBorrowIndex);
                emit Events.P2PBorrowDeltaUpdated(poolToken, deltas.p2pBorrowDelta);
            }

            deltas.p2pSupplyAmount -= Math.min(deltas.p2pSupplyAmount, amount.rayDiv(indexes.p2pSupplyIndex));
            deltas.p2pBorrowAmount -= Math.min(deltas.p2pBorrowAmount, unmatched.rayDiv(indexes.p2pBorrowIndex));
            emit Events.P2PAmountsUpdated(poolToken, deltas.p2pSupplyAmount, deltas.p2pBorrowAmount);
            toBorrow = amount;
        }

        if (inP2P == 0 && onPool == 0) _userMarkets[user].setSupplying(market.borrowMask, false);
    }
}
