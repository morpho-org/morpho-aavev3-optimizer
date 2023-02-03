// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "src/libraries/Types.sol";
import {InterestRatesLib} from "src/libraries/InterestRatesLib.sol";
import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {Test} from "@forge-std/Test.sol";

contract TestInterestRatesLib is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant MIN_INDEX = WadRayMath.RAY;
    uint256 internal constant MAX_INDEX = WadRayMath.RAY * 1000;
    uint256 internal constant MIN_GROWTH_FACTOR = WadRayMath.RAY;
    uint256 internal constant MAX_GROWTH_FACTOR = WadRayMath.RAY * 1000;
    uint256 internal constant MAX_P2P_INDEX_CURSOR = PercentageMath.PERCENTAGE_FACTOR;
    uint256 internal constant MAX_RESERVE_FACTOR = PercentageMath.PERCENTAGE_FACTOR;
    uint256 internal constant MAX_PROPORTION_IDLE = PercentageMath.PERCENTAGE_FACTOR;
    uint256 internal constant MAX_DELTA = 1e9 ether;
    uint256 internal constant MAX_TOTAL_P2P = 1e9 ether;

    function testComputeP2PIndexes(uint256 seed) public {
        Types.IndexesParams memory indexesParams;
        indexesParams.lastSupplyIndexes.poolIndex = bound(_rng(seed, "lastSupplyPoolIndex"), MIN_INDEX, MAX_INDEX);
        indexesParams.lastSupplyIndexes.p2pIndex = bound(_rng(seed, "lastSupplyP2PIndex"), MIN_INDEX, MAX_INDEX);
        indexesParams.lastBorrowIndexes.poolIndex = bound(_rng(seed, "lastBorrowPoolIndex"), MIN_INDEX, MAX_INDEX);
        indexesParams.lastBorrowIndexes.p2pIndex = bound(_rng(seed, "lastBorrowP2PIndex"), MIN_INDEX, MAX_INDEX);
        indexesParams.poolSupplyIndex =
            bound(_rng(seed, "poolSupplyIndex"), indexesParams.lastSupplyIndexes.poolIndex, MAX_INDEX);
        indexesParams.poolBorrowIndex =
            bound(_rng(seed, "poolBorrowIndex"), indexesParams.lastBorrowIndexes.poolIndex, MAX_INDEX);
        indexesParams.reserveFactor = bound(_rng(seed, "reserveFactor"), 0, MAX_RESERVE_FACTOR);
        indexesParams.p2pIndexCursor = bound(_rng(seed, "p2pIndexCursor"), 0, MAX_P2P_INDEX_CURSOR);
        indexesParams.deltas.supply.scaledDeltaPool = bound(_rng(seed, "supplyDeltaPool"), 0, MAX_DELTA);
        indexesParams.deltas.supply.scaledTotalP2P = bound(_rng(seed, "supplyTotalP2P"), 0, MAX_TOTAL_P2P);
        indexesParams.deltas.borrow.scaledDeltaPool = bound(_rng(seed, "borrowDeltaPool"), 0, MAX_DELTA);
        indexesParams.deltas.borrow.scaledTotalP2P = bound(_rng(seed, "borrowTotalP2P"), 0, MAX_TOTAL_P2P);
        indexesParams.proportionIdle = bound(_rng(seed, "proportionIdle"), 0, MAX_PROPORTION_IDLE);

        Types.GrowthFactors memory expectedGrowthFactors = InterestRatesLib.computeGrowthFactors(
            indexesParams.poolSupplyIndex,
            indexesParams.poolBorrowIndex,
            indexesParams.lastSupplyIndexes.poolIndex,
            indexesParams.lastBorrowIndexes.poolIndex,
            indexesParams.p2pIndexCursor,
            indexesParams.reserveFactor
        );

        uint256 expectedP2PSupplyIndex = InterestRatesLib.computeP2PIndex(
            expectedGrowthFactors.poolSupplyGrowthFactor,
            expectedGrowthFactors.p2pSupplyGrowthFactor,
            indexesParams.lastSupplyIndexes,
            indexesParams.deltas.supply.scaledDeltaPool,
            indexesParams.deltas.supply.scaledTotalP2P,
            indexesParams.proportionIdle
        );

        uint256 expectedP2PBorrowIndex = InterestRatesLib.computeP2PIndex(
            expectedGrowthFactors.poolBorrowGrowthFactor,
            expectedGrowthFactors.p2pBorrowGrowthFactor,
            indexesParams.lastBorrowIndexes,
            indexesParams.deltas.borrow.scaledDeltaPool,
            indexesParams.deltas.borrow.scaledTotalP2P,
            0
        );

        (uint256 actualP2PSupplyIndex, uint256 actualP2PBorrowIndex) = InterestRatesLib.computeP2PIndexes(indexesParams);

        assertEq(actualP2PSupplyIndex, expectedP2PSupplyIndex, "p2p supply index");
        assertEq(actualP2PBorrowIndex, expectedP2PBorrowIndex, "p2p borrow index");
    }

    function testComputeGrowthFactorsNormal(
        uint256 newPoolSupplyIndex,
        uint256 newPoolBorrowIndex,
        uint256 lastPoolSupplyIndex,
        uint256 lastPoolBorrowIndex,
        uint256 p2pIndexCursor,
        uint256 reserveFactor
    ) public {
        newPoolSupplyIndex = bound(newPoolSupplyIndex, MIN_INDEX, MAX_INDEX);
        newPoolBorrowIndex = bound(newPoolBorrowIndex, MIN_INDEX, MAX_INDEX);
        lastPoolSupplyIndex = bound(lastPoolSupplyIndex, MIN_INDEX, newPoolSupplyIndex);
        lastPoolBorrowIndex = bound(lastPoolBorrowIndex, MIN_INDEX, newPoolBorrowIndex);
        p2pIndexCursor = bound(p2pIndexCursor, 0, MAX_P2P_INDEX_CURSOR);
        reserveFactor = bound(reserveFactor, 0, MAX_RESERVE_FACTOR);

        Types.GrowthFactors memory expectedGrowthFactors;

        expectedGrowthFactors.poolSupplyGrowthFactor = newPoolSupplyIndex.rayDiv(lastPoolSupplyIndex);
        expectedGrowthFactors.poolBorrowGrowthFactor = newPoolBorrowIndex.rayDiv(lastPoolBorrowIndex);
        vm.assume(expectedGrowthFactors.poolSupplyGrowthFactor <= expectedGrowthFactors.poolBorrowGrowthFactor);

        uint256 p2pGrowthFactor = PercentageMath.weightedAvg(
            expectedGrowthFactors.poolSupplyGrowthFactor, expectedGrowthFactors.poolBorrowGrowthFactor, p2pIndexCursor
        );
        expectedGrowthFactors.p2pSupplyGrowthFactor =
            p2pGrowthFactor - (p2pGrowthFactor - expectedGrowthFactors.poolSupplyGrowthFactor).percentMul(reserveFactor);
        expectedGrowthFactors.p2pBorrowGrowthFactor =
            p2pGrowthFactor + (expectedGrowthFactors.poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(reserveFactor);

        Types.GrowthFactors memory actualGrowthFactors = InterestRatesLib.computeGrowthFactors(
            newPoolSupplyIndex,
            newPoolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            p2pIndexCursor,
            reserveFactor
        );

        assertEq(
            actualGrowthFactors.poolSupplyGrowthFactor,
            expectedGrowthFactors.poolSupplyGrowthFactor,
            "poolSupplyGrowthFactor"
        );
        assertEq(
            actualGrowthFactors.poolBorrowGrowthFactor,
            expectedGrowthFactors.poolBorrowGrowthFactor,
            "poolBorrowGrowthFactor"
        );
        assertEq(
            actualGrowthFactors.p2pSupplyGrowthFactor,
            expectedGrowthFactors.p2pSupplyGrowthFactor,
            "p2pSupplyGrowthFactor"
        );
        assertEq(
            actualGrowthFactors.p2pBorrowGrowthFactor,
            expectedGrowthFactors.p2pBorrowGrowthFactor,
            "p2pBorrowGrowthFactor"
        );
        // Sanity checks
        assertGe(actualGrowthFactors.poolSupplyGrowthFactor, MIN_GROWTH_FACTOR, "too low poolSupplyGrowthFactor");
        assertGe(actualGrowthFactors.poolBorrowGrowthFactor, MIN_GROWTH_FACTOR, "too low poolBorrowGrowthFactor");
        assertGe(actualGrowthFactors.p2pSupplyGrowthFactor, MIN_GROWTH_FACTOR, "too low p2pSupplyGrowthFactor");
        assertGe(actualGrowthFactors.p2pBorrowGrowthFactor, MIN_GROWTH_FACTOR, "too low p2pBorrowGrowthFactor");
    }

    function testComputeGrowthFactorsWhenSupplyGrowsFaster(
        uint256 newPoolSupplyIndex,
        uint256 newPoolBorrowIndex,
        uint256 lastPoolSupplyIndex,
        uint256 lastPoolBorrowIndex,
        uint256 p2pIndexCursor,
        uint256 reserveFactor
    ) public {
        newPoolSupplyIndex = bound(newPoolSupplyIndex, MIN_INDEX, MAX_INDEX);
        newPoolBorrowIndex = bound(newPoolBorrowIndex, MIN_INDEX, MAX_INDEX);
        lastPoolSupplyIndex = bound(lastPoolSupplyIndex, MIN_INDEX, newPoolSupplyIndex);
        lastPoolBorrowIndex = bound(lastPoolBorrowIndex, MIN_INDEX, newPoolBorrowIndex);
        p2pIndexCursor = bound(p2pIndexCursor, 0, MAX_P2P_INDEX_CURSOR);
        reserveFactor = bound(reserveFactor, 0, MAX_RESERVE_FACTOR);

        uint256 expectedPoolSupplyGrowthFactor = newPoolSupplyIndex.rayDiv(lastPoolSupplyIndex);
        uint256 expectedPoolBorrowGrowthFactor = newPoolBorrowIndex.rayDiv(lastPoolBorrowIndex);

        vm.assume(expectedPoolSupplyGrowthFactor > expectedPoolBorrowGrowthFactor);

        Types.GrowthFactors memory actualGrowthFactors = InterestRatesLib.computeGrowthFactors(
            newPoolSupplyIndex,
            newPoolBorrowIndex,
            lastPoolSupplyIndex,
            lastPoolBorrowIndex,
            p2pIndexCursor,
            reserveFactor
        );

        assertEq(actualGrowthFactors.poolSupplyGrowthFactor, expectedPoolSupplyGrowthFactor, "poolSupplyGrowthFactor");
        assertEq(actualGrowthFactors.poolBorrowGrowthFactor, expectedPoolBorrowGrowthFactor, "poolBorrowGrowthFactor");
        assertEq(actualGrowthFactors.p2pSupplyGrowthFactor, expectedPoolBorrowGrowthFactor, "p2pSupplyGrowthFactor");
        assertEq(actualGrowthFactors.p2pBorrowGrowthFactor, expectedPoolBorrowGrowthFactor, "p2pBorrowGrowthFactor");
        // Sanity checks
        assertGe(actualGrowthFactors.poolSupplyGrowthFactor, MIN_GROWTH_FACTOR, "too low poolSupplyGrowthFactor");
        assertGe(actualGrowthFactors.poolBorrowGrowthFactor, MIN_GROWTH_FACTOR, "too low poolBorrowGrowthFactor");
        assertGe(actualGrowthFactors.p2pSupplyGrowthFactor, MIN_GROWTH_FACTOR, "too low p2pSupplyGrowthFactor");
        assertGe(actualGrowthFactors.p2pBorrowGrowthFactor, MIN_GROWTH_FACTOR, "too low p2pBorrowGrowthFactor");
    }

    function testComputeP2PIndex(
        uint256 poolGrowthFactor,
        uint256 p2pGrowthFactor,
        uint256 lastPoolIndex,
        uint256 lastP2PIndex,
        uint256 p2pDelta,
        uint256 p2pAmount,
        uint256 proportionIdle
    ) public {
        poolGrowthFactor = bound(poolGrowthFactor, MIN_INDEX, MAX_INDEX);
        p2pGrowthFactor = bound(p2pGrowthFactor, MIN_INDEX, MAX_INDEX);
        lastPoolIndex = bound(lastPoolIndex, MIN_INDEX, MAX_INDEX);
        lastP2PIndex = bound(lastP2PIndex, MIN_INDEX, MAX_INDEX);
        p2pDelta = bound(p2pDelta, 1, MAX_DELTA);
        p2pAmount = bound(p2pAmount, 1, MAX_TOTAL_P2P);
        proportionIdle = bound(proportionIdle, 0, MAX_PROPORTION_IDLE);

        uint256 expectedProportionDelta = Math.min(
            p2pDelta.rayMul(lastPoolIndex).rayDivUp(p2pAmount.rayMul(lastP2PIndex)), WadRayMath.RAY - proportionIdle
        );
        uint256 expectedP2PIndex = (p2pDelta == 0 || p2pAmount == 0)
            ? lastP2PIndex.rayMul(p2pAmount)
            : lastP2PIndex.rayMul(
                p2pGrowthFactor.rayMul(WadRayMath.RAY - expectedProportionDelta - proportionIdle)
                    + poolGrowthFactor.rayMul(expectedProportionDelta) + proportionIdle
            );
        uint256 actualP2PIndex = InterestRatesLib.computeP2PIndex(
            poolGrowthFactor,
            p2pGrowthFactor,
            Types.MarketSideIndexes256(lastPoolIndex, lastP2PIndex),
            p2pDelta,
            p2pAmount,
            proportionIdle
        );

        assertEq(actualP2PIndex, expectedP2PIndex, "p2pIndex");
    }

    function _rng(uint256 seed, string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }
}
