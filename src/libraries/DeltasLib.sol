// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Events} from "./Events.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

/// @title DeltasLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library used to ease delta reads and writes.
library DeltasLib {
    using Math for uint256;
    using WadRayMath for uint256;

    /// @notice Increases the peer-to-peer amounts following a promotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param promoted The amount to increase the promoted peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to increase the opposite peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    /// @param borrowSide True if this follows borrower promotions. False for supplier promotions.
    /// @return p2pBalanceIncrease The balance amount in peer-to-peer to increase.
    function increaseP2P(
        Types.Deltas storage deltas,
        address underlying,
        uint256 promoted,
        uint256 amount,
        Types.Indexes256 memory indexes,
        bool borrowSide
    ) internal returns (uint256 p2pBalanceIncrease) {
        if (amount == 0) return 0; // promoted == 0 is not checked since promoted <= amount.

        Types.MarketSideDelta storage promotedDelta = borrowSide ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrowSide ? deltas.supply : deltas.borrow;
        Types.MarketSideIndexes256 memory promotedIndexes = borrowSide ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrowSide ? indexes.supply : indexes.borrow;

        p2pBalanceIncrease = amount.rayDiv(counterIndexes.p2pIndex);
        promotedDelta.scaledTotalP2P += promoted.rayDiv(promotedIndexes.p2pIndex);
        counterDelta.scaledTotalP2P += p2pBalanceIncrease;

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    /// @notice Decreases the peer-to-peer amounts following a demotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param demoted The amount to decrease the demoted peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to decrease the opposite peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    /// @param borrowSide True if this follows borrower demotions. False for supplier demotions.
    function decreaseP2P(
        Types.Deltas storage deltas,
        address underlying,
        uint256 demoted,
        uint256 amount,
        Types.Indexes256 memory indexes,
        bool borrowSide
    ) internal {
        if (amount == 0) return; // demoted == 0 is not checked since demoted <= amount.

        Types.MarketSideDelta storage demotedDelta = borrowSide ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrowSide ? deltas.supply : deltas.borrow;
        Types.MarketSideIndexes256 memory demotedIndexes = borrowSide ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrowSide ? indexes.supply : indexes.borrow;

        demotedDelta.scaledTotalP2P = demotedDelta.scaledTotalP2P.zeroFloorSub(demoted.rayDiv(demotedIndexes.p2pIndex));
        counterDelta.scaledTotalP2P = counterDelta.scaledTotalP2P.zeroFloorSub(amount.rayDiv(counterIndexes.p2pIndex));

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }

    /// @notice Calculates & deducts the reserve fee to repay from the given amount, updating the total peer-to-peer amount.
    /// @dev Should only be called if amount or borrow delta is zero.
    /// @param amount The amount to repay/withdraw.
    /// @param indexes The current indexes.
    /// @return The new amount left to process, the fee repaid.
    function repayFee(Types.Deltas storage deltas, uint256 amount, Types.Indexes256 memory indexes)
        internal
        view
        returns (uint256, uint256)
    {
        if (amount == 0) return (0, 0);

        uint256 scaledTotalBorrowP2P = deltas.borrow.scaledTotalP2P;
        // Fee = (borrow.totalScaledP2P - borrow.delta) - (supply.totalScaledP2P - supply.delta).
        uint256 repaidFee = scaledTotalBorrowP2P.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                deltas.supply.scaledDeltaPool.rayMul(indexes.supply.poolIndex)
            )
        );

        if (repaidFee == 0) return (amount, 0);

        repaidFee = Math.min(repaidFee, amount);

        return (amount - repaidFee, repaidFee);
    }
}
