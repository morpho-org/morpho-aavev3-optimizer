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

    /// @notice Increases the peer-to-peer amounts following a supplier promotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param promoted The amount to increase the promoted side peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to increase the opposite side peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    /// @return p2pBalanceIncrease The balance amount in peer-to-peer to increase.
    function increaseP2PTotalSupply(
        Types.Deltas storage deltas,
        address underlying,
        uint256 promoted,
        uint256 amount,
        Types.Indexes256 memory indexes
    ) internal returns (uint256 p2pBalanceIncrease) {
        p2pBalanceIncrease = amount.rayDiv(indexes.borrow.p2pIndex);
        deltas.supply.scaledP2PTotal += promoted.rayDiv(indexes.supply.p2pIndex);
        deltas.borrow.scaledP2PTotal += p2pBalanceIncrease;

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledP2PTotal, deltas.borrow.scaledP2PTotal);
    }

    /// @notice Increases the peer-to-peer amounts following a borrower promotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param promoted The amount to increase the promoted side peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to increase the opposite side peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    /// @return p2pBalanceIncrease The balance amount in peer-to-peer to increase.
    function increaseP2PTotalBorrow(
        Types.Deltas storage deltas,
        address underlying,
        uint256 promoted,
        uint256 amount,
        Types.Indexes256 memory indexes
    ) internal returns (uint256 p2pBalanceIncrease) {
        p2pBalanceIncrease = amount.rayDiv(indexes.supply.p2pIndex);
        deltas.borrow.scaledP2PTotal += promoted.rayDiv(indexes.borrow.p2pIndex);
        deltas.supply.scaledP2PTotal += p2pBalanceIncrease;

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledP2PTotal, deltas.borrow.scaledP2PTotal);
    }

    /// @notice Decreases the peer-to-peer amounts following a supplier demotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param demoted The amount to decrease the demoted side peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to decrease the opposite side peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    function decreaseP2PTotalSupply(
        Types.Deltas storage deltas,
        address underlying,
        uint256 demoted,
        uint256 amount,
        Types.Indexes256 memory indexes
    ) internal {
        if (amount == 0) return; // demoted == 0 is not checked since demoted <= amount.
        deltas.supply.scaledP2PTotal =
            deltas.supply.scaledP2PTotal.zeroFloorSub(demoted.rayDiv(indexes.supply.p2pIndex));
        deltas.borrow.scaledP2PTotal = deltas.borrow.scaledP2PTotal.zeroFloorSub(amount.rayDiv(indexes.borrow.p2pIndex));

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledP2PTotal, deltas.borrow.scaledP2PTotal);
    }

    /// @notice Decreases the peer-to-peer amounts following a borrower demotion.
    /// @param deltas The market deltas to update.
    /// @param underlying The underlying address.
    /// @param demoted The amount to decrease the demoted side peer-to-peer total (in underlying). Must be lower than or equal to amount.
    /// @param amount The amount to decrease the opposite side peer-to-peer total (in underlying).
    /// @param indexes The current indexes.
    function decreaseP2PTotalBorrow(
        Types.Deltas storage deltas,
        address underlying,
        uint256 demoted,
        uint256 amount,
        Types.Indexes256 memory indexes
    ) internal {
        if (amount == 0) return; // demoted == 0 is not checked since demoted <= amount.
        deltas.borrow.scaledP2PTotal =
            deltas.borrow.scaledP2PTotal.zeroFloorSub(demoted.rayDiv(indexes.borrow.p2pIndex));
        deltas.supply.scaledP2PTotal = deltas.supply.scaledP2PTotal.zeroFloorSub(amount.rayDiv(indexes.supply.p2pIndex));

        emit Events.P2PTotalsUpdated(underlying, deltas.supply.scaledP2PTotal, deltas.borrow.scaledP2PTotal);
    }

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
}
