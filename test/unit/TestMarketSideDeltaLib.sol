// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Types} from "src/libraries/Types.sol";
import {Events} from "src/libraries/Events.sol";
import {MarketSideDeltaLib} from "src/libraries/MarketSideDeltaLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";

import {Test} from "@forge-std/Test.sol";

contract TestUnitMarketSideDeltaLib is Test {
    using MarketSideDeltaLib for Types.MarketSideDelta;
    using WadRayMath for uint256;
    using Math for uint256;

    uint256 internal constant MAX_AMOUNT = 1e20 ether;

    Types.MarketSideDelta internal delta;
    Types.MarketSideIndexes256 internal marketSideIndex;

    function setUp() public {
        marketSideIndex = Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY);
    }

    function testIncreaseDeltaZeroAmount(address underlying, uint256 scaledDeltaPool, uint256 scaledTotalP2P) public {
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        delta.increaseDelta(underlying, 0, marketSideIndex, true);

        assertEq(delta.scaledDeltaPool, scaledDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testIncreaseDeltaBorrow(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        uint256 expectedDeltaPool = scaledDeltaPool + amount.rayDiv(marketSideIndex.poolIndex);

        vm.expectEmit(true, true, true, true);
        emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);
        delta.increaseDelta(underlying, amount, marketSideIndex, true);

        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testIncreaseDeltaSupply(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        uint256 expectedDeltaPool = scaledDeltaPool + amount.rayDiv(marketSideIndex.poolIndex);

        vm.expectEmit(true, true, true, true);
        emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);
        delta.increaseDelta(underlying, amount, marketSideIndex, false);

        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testDecreaseDeltaWhenDeltaIsZero(address underlying, uint256 amount, uint256 scaledTotalP2P) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);

        delta.scaledTotalP2P = scaledTotalP2P;

        delta.decreaseDelta(underlying, 0, marketSideIndex.poolIndex, true);

        assertEq(delta.scaledDeltaPool, 0);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testDecreaseDeltaBorrow(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P
    ) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 1, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        uint256 expectedDecreased = Math.min(scaledDeltaPool.rayMulUp(marketSideIndex.poolIndex), amount);
        uint256 expectedDeltaPool =
            scaledDeltaPool.zeroFloorSub(expectedDecreased.rayDivDown(marketSideIndex.poolIndex));
        uint256 expectedToProcess = amount - expectedDecreased;

        vm.expectEmit(true, true, true, true);
        emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);

        (uint256 toProcess, uint256 toRepayOrWithdraw) =
            delta.decreaseDelta(underlying, amount, marketSideIndex.poolIndex, true);

        assertEq(toProcess, expectedToProcess);
        assertEq(toRepayOrWithdraw, expectedDecreased);
        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testDecreaseDeltaSupply(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P
    ) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 1, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        uint256 expectedDecreased = Math.min(scaledDeltaPool.rayMulUp(marketSideIndex.poolIndex), amount);
        uint256 expectedDeltaPool =
            scaledDeltaPool.zeroFloorSub(expectedDecreased.rayDivDown(marketSideIndex.poolIndex));
        uint256 expectedToProcess = amount - expectedDecreased;

        vm.expectEmit(true, true, true, true);
        emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);

        (uint256 toProcess, uint256 toRepayOrWithdraw) =
            delta.decreaseDelta(underlying, amount, marketSideIndex.poolIndex, false);

        assertEq(toProcess, expectedToProcess);
        assertEq(toRepayOrWithdraw, expectedDecreased);
        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }
}
