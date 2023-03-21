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

    /// @notice Calculates & deducts the reserve fee to repay from the given amount, updating the total peer-to-peer amount.
    /// @dev Should only be called if amount or borrow delta is zero.
    /// @param amount The amount to repay/withdraw (in underlying).
    /// @param indexes The current indexes.
    /// @return The new amount left to process (in underlying).
    function repayFee(Types.Deltas storage deltas, uint256 amount, Types.Indexes256 memory indexes)
        internal
        returns (uint256)
    {
        if (amount == 0) return 0;

        uint256 scaledTotalBorrowP2P = deltas.borrow.scaledP2PTotal;
        // Fee = (borrow.totalP2P - borrow.delta) - (supply.totalP2P - supply.delta).
        uint256 feeToRepay = scaledTotalBorrowP2P.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)
            )
        );

        if (feeToRepay == 0) return amount;

        feeToRepay = Math.min(feeToRepay, amount);
        deltas.borrow.scaledP2PTotal = scaledTotalBorrowP2P.zeroFloorSub(feeToRepay.rayDivDown(indexes.borrow.p2pIndex)); // P2PTotalsUpdated emitted in `decreaseP2P`.

        return amount - feeToRepay;
    }

    function emitP2PTotalsUpdated(Types.Deltas storage deltas, address underlying) internal {
        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledP2PTotal, deltas.borrow.scaledP2PTotal);
    }
}
