// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Events} from "./Events.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library DeltasLib {
    using Math for uint256;
    using WadRayMath for uint256;

    /// @notice Increases the peer-to-peer amounts following a promotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param promoted The amount promoted (in underlying).
    /// @param scaledInP2P The amount in peer-to-peer (in peer-to-peer unit).
    /// @param p2pIndex The current peer-to-peer index.
    /// @return The new amount in peer-to-peer.
    function increaseP2P(
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

    /// @notice Decreases the peer-to-peer amounts following a demotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param demoted The amount demoted (in underlying).
    /// @param amount The amount to supply/borrow (in underlying).
    /// @param indexes The current indexes.
    /// @param borrowSide Whether the demotion was performed on the borrow side.
    function decreaseP2P(
        Types.Deltas storage deltas,
        address underlying,
        uint256 demoted,
        uint256 amount,
        Types.Indexes256 memory indexes,
        bool borrowSide
    ) internal {
        Types.MarketSideDelta storage demotedDelta = borrowSide ? deltas.borrow : deltas.supply;
        Types.MarketSideDelta storage counterDelta = borrowSide ? deltas.supply : deltas.borrow;
        Types.MarketSideIndexes256 memory demotedIndexes = borrowSide ? indexes.borrow : indexes.supply;
        Types.MarketSideIndexes256 memory counterIndexes = borrowSide ? indexes.supply : indexes.borrow;

        // zeroFloorSub as the last decimal might flip.
        demotedDelta.scaledTotalP2P = demotedDelta.scaledTotalP2P.zeroFloorSub(demoted.rayDiv(demotedIndexes.p2pIndex));
        counterDelta.scaledTotalP2P = counterDelta.scaledTotalP2P.zeroFloorSub(amount.rayDiv(counterIndexes.p2pIndex));

        emit Events.P2PAmountsUpdated(underlying, deltas.supply.scaledTotalP2P, deltas.borrow.scaledTotalP2P);
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
}
