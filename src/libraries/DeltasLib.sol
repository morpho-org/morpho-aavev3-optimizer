// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

library DeltasLib {
    using Math for uint256;
    using WadRayMath for uint256;

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
