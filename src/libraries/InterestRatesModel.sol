// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Types} from "./Types.sol";
import {WadRayMath} from "morpho-utils/math/WadRayMath.sol";
import {Math} from "morpho-utils/math/Math.sol";
import {PercentageMath} from "morpho-utils/math/PercentageMath.sol";

library InterestRatesModel {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function computeP2PIndexes(Types.IRMParams memory params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        // Compute pool growth factors
        Types.GrowthFactors memory growthFactors = computeGrowthFactors(
            params.poolSupplyIndex,
            params.poolBorrowIndex,
            params.lastPoolSupplyIndex,
            params.lastPoolBorrowIndex,
            params.p2pIndexCursor,
            params.reserveFactor
        );
        newP2PSupplyIndex = computeP2PIndex(
            growthFactors.poolSupplyGrowthFactor,
            growthFactors.p2pSupplyGrowthFactor,
            params.lastPoolSupplyIndex,
            params.lastP2PSupplyIndex,
            params.deltas.p2pSupplyDelta,
            params.deltas.p2pSupplyAmount
        );
        newP2PBorrowIndex = computeP2PIndex(
            growthFactors.poolBorrowGrowthFactor,
            growthFactors.p2pBorrowGrowthFactor,
            params.lastPoolBorrowIndex,
            params.lastP2PBorrowIndex,
            params.deltas.p2pBorrowDelta,
            params.deltas.p2pBorrowAmount
        );
    }

    /// @notice Computes and returns the new growth factors associated to a given pool's supply/borrow index & Morpho's peer-to-peer index.
    /// @param newPoolSupplyIndex The pool's current supply index.
    /// @param newPoolBorrowIndex The pool's current borrow index.
    /// @param lastPoolSupplyIndex The pool's last supply index.
    /// @param lastPoolBorrowIndex The pool's last borrow index.
    /// @param p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @param reserveFactor The reserve factor of the given market.
    /// @return growthFactors The market's indexes growth factors (in ray).
    function computeGrowthFactors(
        uint256 newPoolSupplyIndex,
        uint256 newPoolBorrowIndex,
        uint256 lastPoolSupplyIndex,
        uint256 lastPoolBorrowIndex,
        uint256 p2pIndexCursor,
        uint256 reserveFactor
    ) internal pure returns (Types.GrowthFactors memory growthFactors) {
        growthFactors.poolSupplyGrowthFactor = newPoolSupplyIndex.rayDiv(lastPoolSupplyIndex);
        growthFactors.poolBorrowGrowthFactor = newPoolBorrowIndex.rayDiv(lastPoolBorrowIndex);

        if (growthFactors.poolSupplyGrowthFactor <= growthFactors.poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = PercentageMath.weightedAvg(
                growthFactors.poolSupplyGrowthFactor, growthFactors.poolBorrowGrowthFactor, p2pIndexCursor
            );

            growthFactors.p2pSupplyGrowthFactor =
                p2pGrowthFactor - (p2pGrowthFactor - growthFactors.poolSupplyGrowthFactor).percentMul(reserveFactor);
            growthFactors.p2pBorrowGrowthFactor =
                p2pGrowthFactor + (growthFactors.poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(reserveFactor);
        } else {
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone has done a flashloan on Aave:
            // the peer-to-peer growth factors are set to the pool borrow growth factor.
            growthFactors.p2pSupplyGrowthFactor = growthFactors.poolBorrowGrowthFactor;
            growthFactors.p2pBorrowGrowthFactor = growthFactors.poolBorrowGrowthFactor;
        }
    }

    /// @notice Computes and returns the new peer-to-peer index of a market given its parameters.
    /// @param poolGrowthFactor The pool growth factor.
    /// @param p2pGrowthFactor The P2P growth factor.
    /// @param lastPoolIndex The last pool index.
    /// @param lastP2PIndex The last P2P index.
    /// @param p2pDelta The last P2P delta.
    /// @param p2pAmount The last P2P amount.
    /// @return newP2PIndex The updated peer-to-peer index (in ray).
    function computeP2PIndex(
        uint256 poolGrowthFactor,
        uint256 p2pGrowthFactor,
        uint256 lastPoolIndex,
        uint256 lastP2PIndex,
        uint256 p2pDelta,
        uint256 p2pAmount
    ) internal pure returns (uint256 newP2PIndex) {
        if (p2pAmount == 0 || p2pDelta == 0) {
            newP2PIndex = lastP2PIndex.rayMul(p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                p2pDelta.wadToRay().rayMul(lastPoolIndex).rayDiv(p2pAmount.wadToRay().rayMul(lastP2PIndex)),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PIndex = lastP2PIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pGrowthFactor) + shareOfTheDelta.rayMul(poolGrowthFactor)
            );
        }
    }
}
