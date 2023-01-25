// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Types} from "src/libraries/Types.sol";
import {DeltasLib} from "src/libraries/DeltasLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Math} from "@morpho-utils/math/Math.sol";

import {Test} from "@forge-std/Test.sol";

contract TestUnitDeltasLib is Test {
    using WadRayMath for uint256;
    using Math for uint256;

    Types.Deltas internal deltas;
    Types.Indexes256 internal indexes;

    uint256 internal constant MIN_AMOUNT = 10;
    uint256 internal constant MAX_AMOUNT = 1e9 ether;

    function setUp() public {
        indexes = Types.Indexes256(
            Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY),
            Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY)
        );
    }

    function testIncreaseP2PShouldReturnZeroIfAmountIsZero() public {
        uint256 promoted = 100;
        uint256 amount = 0;
        uint256 newP2P = DeltasLib.increaseP2P(deltas, address(1), promoted, amount, indexes, false);
        assertEq(newP2P, 0);
    }

    function testIncreaseP2PSupply(uint256 promoted, uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow)
        public
    {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        promoted = bound(promoted, 0, amount);
        totalP2PSupply = bound(totalP2PSupply, 0, MAX_AMOUNT);
        totalP2PBorrow = bound(totalP2PBorrow, 0, MAX_AMOUNT);
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        uint256 newP2P = DeltasLib.increaseP2P(deltas, address(1), promoted, amount, indexes, false);
        assertEq(newP2P, promoted.rayDiv(indexes.supply.p2pIndex));
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply + newP2P);
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow + amount.rayDiv(indexes.borrow.p2pIndex));
    }

    function testIncreaseP2PBorrow(uint256 promoted, uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow)
        public
    {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        promoted = bound(promoted, 0, amount);
        totalP2PSupply = bound(totalP2PSupply, 0, MAX_AMOUNT);
        totalP2PBorrow = bound(totalP2PBorrow, 0, MAX_AMOUNT);
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        uint256 newP2P = DeltasLib.increaseP2P(deltas, address(1), promoted, amount, indexes, true);
        assertEq(newP2P, promoted.rayDiv(indexes.borrow.p2pIndex));
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply + amount.rayDiv(indexes.supply.p2pIndex));
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow + newP2P);
    }

    function testDecreaseP2PSupplyShouldNotChangeDeltasIfAmountIsZero() public {
        uint256 demoted = 100;
        uint256 amount = 0;
        uint256 totalP2PSupply = 1000;
        uint256 totalP2PBorrow = 1000;
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        DeltasLib.decreaseP2P(deltas, address(1), demoted, amount, indexes, false);
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply);
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow);
    }

    function testDecreaseP2PSupply(uint256 demoted, uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow)
        public
    {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        demoted = bound(demoted, 0, amount);
        totalP2PSupply = bound(totalP2PSupply, 0, MAX_AMOUNT);
        totalP2PBorrow = bound(totalP2PBorrow, 0, MAX_AMOUNT);
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        DeltasLib.decreaseP2P(deltas, address(1), demoted, amount, indexes, false);
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply.zeroFloorSub(demoted.rayDiv(indexes.supply.p2pIndex)));
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow.zeroFloorSub(amount.rayDiv(indexes.borrow.p2pIndex)));
    }

    function testDecreaseP2PBorrow(uint256 demoted, uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow)
        public
    {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        demoted = bound(demoted, 0, amount);
        totalP2PSupply = bound(totalP2PSupply, 0, MAX_AMOUNT);
        totalP2PBorrow = bound(totalP2PBorrow, 0, MAX_AMOUNT);
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        DeltasLib.decreaseP2P(deltas, address(1), demoted, amount, indexes, true);
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply.zeroFloorSub(amount.rayDiv(indexes.supply.p2pIndex)));
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow.zeroFloorSub(demoted.rayDiv(indexes.borrow.p2pIndex)));
    }

    function testRepayFeeShouldReturnZeroIfAmountIsZero() public {
        uint256 amount = 0;
        uint256 totalP2PSupply = 1000;
        uint256 totalP2PBorrow = 1000;
        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        uint256 fee = DeltasLib.repayFee(deltas, amount, indexes);
        assertEq(fee, 0);
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply);
        assertEq(deltas.borrow.scaledTotalP2P, totalP2PBorrow);
    }

    function testRepayFee(uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow, uint256 supplyDelta) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        totalP2PSupply = bound(totalP2PSupply, 0, MAX_AMOUNT);
        totalP2PBorrow = bound(totalP2PBorrow, 0, MAX_AMOUNT);
        supplyDelta = bound(supplyDelta, 0, totalP2PSupply);

        deltas.supply.scaledTotalP2P = totalP2PSupply;
        deltas.borrow.scaledTotalP2P = totalP2PBorrow;
        deltas.supply.scaledDeltaPool = supplyDelta;

        uint256 expectedFee = totalP2PBorrow.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            totalP2PSupply.rayMul(indexes.supply.p2pIndex).zeroFloorSub(supplyDelta.rayMul(indexes.supply.poolIndex))
        );
        expectedFee = Math.min(amount, expectedFee);
        uint256 toProcess = DeltasLib.repayFee(deltas, amount, indexes);
        assertEq(toProcess, amount - expectedFee, "expected fee");
        assertEq(deltas.supply.scaledTotalP2P, totalP2PSupply, "supply total");
        assertEq(
            deltas.borrow.scaledTotalP2P,
            totalP2PBorrow.zeroFloorSub(expectedFee.rayDiv(indexes.borrow.p2pIndex)),
            "borrow total"
        );
    }
}
