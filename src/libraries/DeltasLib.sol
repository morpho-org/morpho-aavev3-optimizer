// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Events} from "./Events.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library DeltasLib {
    using Math for uint256;
    using WadRayMath for uint256;

    /// @notice Updates the delta and p2p amounts for a repay or withdraw after a promotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param promoted The amount promoted (in underlying).
    /// @param scaledInP2P The amount in p2p (in peer-to-peer unit).
    /// @param p2pIndex The current p2p index.
    /// @return The new amount in p2p.
    function addToP2P(
        Types.Deltas storage deltas,
        address underlying,
        uint256 promoted,
        uint256 scaledInP2P,
        uint256 p2pIndex
    ) internal returns (uint256) {
        if (promoted == 0) return scaledInP2P;

        uint256 promotedP2P = promoted.rayDivDown(p2pIndex);
        deltas.supply.scaledTotalP2P += promotedP2P;
        deltas.borrow.scaledTotalP2P += promotedP2P;

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);

        return scaledInP2P + promotedP2P;
    }

    /// @notice Calculates & deducts the reserve fee to repay from the given amount, updating the total peer-to-peer amount.
    /// @param amount The amount to repay/withdraw.
    /// @param indexes The current indexes.
    /// @return The new amount left to process.
    function repayFee(Types.Deltas storage deltas, uint256 amount, Types.Indexes256 memory indexes)
        internal
        returns (uint256)
    {
        if (amount == 0) return 0;

        uint256 scaledTotalBorrowP2P = deltas.borrow.scaledTotalP2P;
        // Fee = (borrow.totalScaledP2P - borrow.delta) - (supply.totalScaledP2P - supply.delta).
        // No need to subtract borrow.delta as it is zero.
        uint256 feeToRepay = scaledTotalBorrowP2P.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                deltas.supply.scaledDeltaPool.rayMul(indexes.supply.poolIndex)
            )
        );

        if (feeToRepay == 0) return amount;

        feeToRepay = Math.min(feeToRepay, amount);
        deltas.borrow.scaledTotalP2P = scaledTotalBorrowP2P.zeroFloorSub(feeToRepay.rayDivDown(indexes.borrow.p2pIndex));

        return amount - feeToRepay;
    }

    /// @notice Given variables from a market side, matches the delta and calculates the amount to supply/borrow from delta.
    ///         Updates the market side delta accordingly.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param poolIndex The current pool index.
    /// @param borrowSide Whether the market side is borrow.
    /// @return The amount to repay/withdraw and the amount left to process.
    function matchDelta(
        Types.Deltas storage deltas,
        address underlying,
        uint256 amount,
        uint256 poolIndex,
        bool borrowSide
    ) internal returns (uint256, uint256) {
        Types.MarketSideDelta storage sideDelta = borrowSide ? deltas.borrow : deltas.supply;

        uint256 scaledDeltaPool = sideDelta.scaledDeltaPool;
        if (scaledDeltaPool == 0) return (0, amount);

        uint256 matchedDelta = Math.min(scaledDeltaPool.rayMulUp(poolIndex), amount); // In underlying.
        uint256 newScaledDeltaPool = scaledDeltaPool.zeroFloorSub(matchedDelta.rayDivDown(poolIndex));

        sideDelta.scaledDeltaPool = newScaledDeltaPool;

        if (borrowSide) emit Events.P2PBorrowDeltaUpdated(underlying, newScaledDeltaPool);
        else emit Events.P2PSupplyDeltaUpdated(underlying, newScaledDeltaPool);

        return (matchedDelta, amount - matchedDelta);
    }

    /// @notice Given variables from a market side, demotes users and calculates the amount to supply/borrow from demote.
    ///         Updates the market side delta accordingly.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param maxLoops The maximum number of loops to run.
    /// @param indexes The current indexes.
    /// @param demoteRoutine The demote function.
    /// @param borrowSide Whether the market side is borrow.
    function demoteSide(
        Types.Deltas storage deltas,
        address underlying,
        uint256 amount,
        uint256 maxLoops,
        Types.Indexes256 memory indexes,
        function(address, uint256, uint256) returns (uint256) demoteRoutine,
        bool borrowSide
    ) internal {
        if (amount == 0) return;

        uint256 demoted = demoteRoutine(underlying, amount, maxLoops);

        Types.MarketSideIndexes256 memory demotedIndexes = borrowSide ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrowSide ? indexes.supply : indexes.borrow;
        Types.MarketSideDelta storage demotedDelta = borrowSide ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrowSide ? deltas.supply : deltas.borrow;

        // Increase the peer-to-peer delta.
        if (demoted < amount) {
            uint256 newScaledDeltaPool =
                demotedDelta.scaledDeltaPool + (amount - demoted).rayDiv(demotedIndexes.poolIndex);

            demotedDelta.scaledDeltaPool = newScaledDeltaPool;

            if (borrowSide) emit Events.P2PBorrowDeltaUpdated(underlying, newScaledDeltaPool);
            else emit Events.P2PSupplyDeltaUpdated(underlying, newScaledDeltaPool);
        }

        // zeroFloorSub as the last decimal might flip.
        demotedDelta.scaledTotalP2P = demotedDelta.scaledTotalP2P.zeroFloorSub(demoted.rayDiv(demotedIndexes.p2pIndex));
        counterDelta.scaledTotalP2P = counterDelta.scaledTotalP2P.zeroFloorSub(amount.rayDiv(counterIndexes.p2pIndex));

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
    }
}
