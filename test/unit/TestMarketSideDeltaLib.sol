// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Types} from "src/libraries/Types.sol";
import {MarketSideDeltaLib} from "src/libraries/MarketSideDeltaLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";

import {Test} from "@forge-std/Test.sol";

contract TestMarketSideDeltaLib is Test {
    using MarketSideDeltaLib for Types.MarketSideDelta;
    using WadRayMath for uint256;
    using Math for uint256;

    uint256 internal constant MIN_AMOUNt = 100;
    uint256 internal constant MAX_AMOUNT = 1e9 ether;

    Types.MarketSideDelta internal delta;
    Types.MarketSideIndexes256 internal marketSideIndex;

    function setUp() public {
        marketSideIndex = Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY);
    }

    function testIncrease(uint256 amount, uint256 poolDelta, uint256 total) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        total = bound(total, 0, MAX_AMOUNT);
        poolDelta = bound(poolDelta, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = poolDelta;
        delta.scaledTotalP2P = total;

        uint256 expectedDeltaPool = poolDelta + amount.rayDiv(marketSideIndex.poolIndex);
        delta.increase(address(0), amount, marketSideIndex, false);
        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, total);
    }

    function testDecrease(uint256 amount, uint256 poolDelta, uint256 total) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        total = bound(total, 0, MAX_AMOUNT);
        poolDelta = bound(poolDelta, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = poolDelta;
        delta.scaledTotalP2P = total;

        uint256 expectedDecreased = Math.min(poolDelta.rayMulUp(marketSideIndex.poolIndex), amount);
        uint256 expectedDeltaPool = poolDelta.zeroFloorSub(expectedDecreased.rayDivDown(marketSideIndex.poolIndex));
        uint256 expectedToProcess = amount - expectedDecreased;

        (uint256 toRepayOrWithdraw, uint256 toProcess) =
            delta.decrease(address(0), amount, marketSideIndex.poolIndex, false);

        assertEq(toRepayOrWithdraw, expectedDecreased);
        assertEq(toProcess, expectedToProcess);
        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, total);
    }
}
