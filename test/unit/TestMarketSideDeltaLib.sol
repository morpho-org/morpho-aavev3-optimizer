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

    uint256 internal constant MAX_AMOUNT = 1e9 ether;

    Types.MarketSideDelta internal delta;
    Types.MarketSideIndexes256 internal marketSideIndex;

    function setUp() public {
        marketSideIndex = Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY);
    }

    function testIncreaseZeroAmount(
        address underlying,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P,
        bool borrowSide
    ) public {
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        delta.increase(underlying, 0, marketSideIndex, borrowSide);

        assertEq(delta.scaledDeltaPool, scaledDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testIncrease(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P,
        bool borrowSide
    ) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);
        scaledDeltaPool = bound(scaledDeltaPool, 0, MAX_AMOUNT);

        delta.scaledDeltaPool = scaledDeltaPool;
        delta.scaledTotalP2P = scaledTotalP2P;

        uint256 expectedDeltaPool = scaledDeltaPool + amount.rayDiv(marketSideIndex.poolIndex);

        vm.expectEmit(true, false, false, true);
        if (borrowSide) emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);
        else emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);
        delta.increase(underlying, amount, marketSideIndex, borrowSide);

        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testDecreaseWhenDeltaIsZero(address underlying, uint256 amount, uint256 scaledTotalP2P, bool borrowSide)
        public
    {
        amount = bound(amount, 0, MAX_AMOUNT);
        scaledTotalP2P = bound(scaledTotalP2P, 0, MAX_AMOUNT);

        delta.scaledTotalP2P = scaledTotalP2P;

        delta.decrease(underlying, 0, marketSideIndex.poolIndex, borrowSide);

        assertEq(delta.scaledDeltaPool, 0);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }

    function testDecrease(
        address underlying,
        uint256 amount,
        uint256 scaledDeltaPool,
        uint256 scaledTotalP2P,
        bool borrowSide
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

        vm.expectEmit(true, false, false, true);
        if (borrowSide) emit Events.P2PBorrowDeltaUpdated(underlying, expectedDeltaPool);
        else emit Events.P2PSupplyDeltaUpdated(underlying, expectedDeltaPool);

        (uint256 toRepayOrWithdraw, uint256 toProcess) =
            delta.decrease(underlying, amount, marketSideIndex.poolIndex, borrowSide);

        assertEq(toRepayOrWithdraw, expectedDecreased);
        assertEq(toProcess, expectedToProcess);
        assertEq(delta.scaledDeltaPool, expectedDeltaPool);
        assertEq(delta.scaledTotalP2P, scaledTotalP2P);
    }
}
