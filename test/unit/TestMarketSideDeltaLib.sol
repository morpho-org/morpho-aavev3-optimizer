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

    function testIncreaseDeltaZeroAmount(address underlying, uint256 scaledP2PDelta, uint256 scaledP2PTotal) public {
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);
        scaledP2PDelta = bound(scaledP2PDelta, 0, MAX_AMOUNT);

        delta.scaledP2PDelta = scaledP2PDelta;
        delta.scaledP2PTotal = scaledP2PTotal;

        delta.increaseDelta(underlying, 0, marketSideIndex, true);

        assertEq(delta.scaledP2PDelta, scaledP2PDelta);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }

    function testIncreaseDeltaBorrow(address underlying, uint256 amount, uint256 scaledP2PDelta, uint256 scaledP2PTotal)
        public
    {
        amount = bound(amount, 1, MAX_AMOUNT);
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);
        scaledP2PDelta = bound(scaledP2PDelta, 0, MAX_AMOUNT);

        delta.scaledP2PDelta = scaledP2PDelta;
        delta.scaledP2PTotal = scaledP2PTotal;

        uint256 expectedDeltaPool = scaledP2PDelta + amount.rayDiv(marketSideIndex.poolIndex);

        vm.expectEmit(true, true, true, true);
        emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);
        delta.increaseDelta(underlying, amount, marketSideIndex, true);

        assertEq(delta.scaledP2PDelta, expectedDeltaPool);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }

    function testIncreaseDeltaSupply(address underlying, uint256 amount, uint256 scaledP2PDelta, uint256 scaledP2PTotal)
        public
    {
        amount = bound(amount, 1, MAX_AMOUNT);
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);
        scaledP2PDelta = bound(scaledP2PDelta, 0, MAX_AMOUNT);

        delta.scaledP2PDelta = scaledP2PDelta;
        delta.scaledP2PTotal = scaledP2PTotal;

        uint256 expectedDeltaPool = scaledP2PDelta + amount.rayDiv(marketSideIndex.poolIndex);

        vm.expectEmit(true, true, true, true);
        emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);
        delta.increaseDelta(underlying, amount, marketSideIndex, false);

        assertEq(delta.scaledP2PDelta, expectedDeltaPool);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }

    function testDecreaseDeltaWhenDeltaIsZero(address underlying, uint256 scaledP2PTotal) public {
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);

        delta.scaledP2PTotal = scaledP2PTotal;

        (uint256 toProcess, uint256 toRepay) = delta.decreaseDelta(underlying, 0, marketSideIndex.poolIndex, true);

        assertEq(toProcess, 0);
        assertEq(toRepay, 0);
        assertEq(delta.scaledP2PDelta, 0);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }

    function testDecreaseDeltaBorrow(address underlying, uint256 amount, uint256 scaledP2PDelta, uint256 scaledP2PTotal)
        public
    {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);
        scaledP2PDelta = bound(scaledP2PDelta, 1, MAX_AMOUNT);

        delta.scaledP2PDelta = scaledP2PDelta;
        delta.scaledP2PTotal = scaledP2PTotal;

        uint256 expectedDecreased = Math.min(scaledP2PDelta.rayMulUp(marketSideIndex.poolIndex), amount);
        uint256 expectedDeltaPool = scaledP2PDelta.zeroFloorSub(expectedDecreased.rayDivDown(marketSideIndex.poolIndex));
        uint256 expectedToProcess = amount - expectedDecreased;

        vm.expectEmit(true, true, true, true);
        emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);

        (uint256 toProcess, uint256 toRepay) = delta.decreaseDelta(underlying, amount, marketSideIndex.poolIndex, true);

        assertEq(toProcess, expectedToProcess);
        assertEq(toRepay, expectedDecreased);
        assertEq(delta.scaledP2PDelta, expectedDeltaPool);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }

    function testDecreaseDeltaSupply(address underlying, uint256 amount, uint256 scaledP2PDelta, uint256 scaledP2PTotal)
        public
    {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledP2PTotal = bound(scaledP2PTotal, 0, MAX_AMOUNT);
        scaledP2PDelta = bound(scaledP2PDelta, 1, MAX_AMOUNT);

        delta.scaledP2PDelta = scaledP2PDelta;
        delta.scaledP2PTotal = scaledP2PTotal;

        uint256 expectedDecreased = Math.min(scaledP2PDelta.rayMulUp(marketSideIndex.poolIndex), amount);
        uint256 expectedDeltaPool = scaledP2PDelta.zeroFloorSub(expectedDecreased.rayDivDown(marketSideIndex.poolIndex));
        uint256 expectedToProcess = amount - expectedDecreased;

        vm.expectEmit(true, true, true, true);
        emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);

        (uint256 toProcess, uint256 toWithdraw) =
            delta.decreaseDelta(underlying, amount, marketSideIndex.poolIndex, false);

        assertEq(toProcess, expectedToProcess);
        assertEq(toWithdraw, expectedDecreased);
        assertEq(delta.scaledP2PDelta, expectedDeltaPool);
        assertEq(delta.scaledP2PTotal, scaledP2PTotal);
    }
}
