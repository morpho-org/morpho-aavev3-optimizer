// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Events} from "./Events.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library MarketSideDeltaLib {
    using Math for uint256;
    using WadRayMath for uint256;

    /// @notice Given variables from a market side, matches the delta and calculates the amount to supply/borrow from delta.
    ///         Updates the market side delta accordingly.
    /// @param underlying The underlying address.
    /// @param amount The amount to supply/borrow.
    /// @param poolIndex The current pool index.
    /// @param borrowSide Whether the market side is borrow.
    /// @return The amount to repay/withdraw and the amount left to process.
    function matchDelta(
        Types.MarketSideDelta storage sideDelta,
        address underlying,
        uint256 amount,
        uint256 poolIndex,
        bool borrowSide
    ) internal returns (uint256, uint256) {
        uint256 scaledDeltaPool = sideDelta.scaledDeltaPool;
        if (scaledDeltaPool == 0) return (0, amount);

        uint256 matchedDelta = Math.min(scaledDeltaPool.rayMulUp(poolIndex), amount); // In underlying.
        uint256 newScaledDeltaPool = scaledDeltaPool.zeroFloorSub(matchedDelta.rayDivDown(poolIndex));

        sideDelta.scaledDeltaPool = newScaledDeltaPool;

        if (borrowSide) emit Events.P2PBorrowDeltaUpdated(underlying, newScaledDeltaPool);
        else emit Events.P2PSupplyDeltaUpdated(underlying, newScaledDeltaPool);

        return (matchedDelta, amount - matchedDelta);
    }

    /// @notice Updates the delta and p2p amounts for a repay or withdraw after a promotion.
    /// @param sideDelta The market side delta to update.
    /// @param toProcess The amount to repay/withdraw.
    /// @param inP2P The amount in p2p.
    /// @param p2pIndex The current p2p index.
    /// @return The new amount in p2p.
    function addToP2P(Types.MarketSideDelta storage sideDelta, uint256 toProcess, uint256 inP2P, uint256 p2pIndex)
        internal
        returns (uint256)
    {
        if (toProcess == 0) return inP2P;

        uint256 toProcessP2P = toProcess.rayDivDown(p2pIndex);
        sideDelta.scaledTotalP2P += toProcessP2P;

        return inP2P + toProcessP2P;
    }
}
