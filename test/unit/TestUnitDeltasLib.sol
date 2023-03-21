// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {DeltasLib} from "src/libraries/DeltasLib.sol";

import "test/helpers/BaseTest.sol";

contract TestUnitDeltasLib is BaseTest {
    using Math for uint256;
    using WadRayMath for uint256;

    Types.Deltas internal deltas;
    Types.Indexes256 internal indexes;

    function setUp() public {
        indexes = Types.Indexes256(
            Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY),
            Types.MarketSideIndexes256(WadRayMath.RAY, WadRayMath.RAY)
        );
    }

    function testRepayFeeShouldReturnZeroIfAmountIsZero(uint256 totalP2PSupply, uint256 totalP2PBorrow) public {
        totalP2PSupply = _boundAmount(totalP2PSupply);
        totalP2PBorrow = _boundAmount(totalP2PBorrow);
        uint256 amount = 0;
        deltas.supply.scaledP2PTotal = totalP2PSupply;
        deltas.borrow.scaledP2PTotal = totalP2PBorrow;
        uint256 fee = DeltasLib.repayFee(deltas, amount, indexes);
        assertEq(fee, 0);
        assertEq(deltas.supply.scaledP2PTotal, totalP2PSupply);
        assertEq(deltas.borrow.scaledP2PTotal, totalP2PBorrow);
    }

    function testRepayFee(uint256 amount, uint256 totalP2PSupply, uint256 totalP2PBorrow, uint256 supplyDelta) public {
        amount = _boundAmountNotZero(amount);
        totalP2PSupply = _boundAmount(totalP2PSupply).rayDiv(indexes.supply.p2pIndex);
        totalP2PBorrow = _boundAmount(totalP2PBorrow).rayDiv(indexes.borrow.p2pIndex);
        supplyDelta =
            bound(supplyDelta, 0, totalP2PSupply).rayMul(indexes.supply.p2pIndex).rayDiv(indexes.supply.poolIndex);

        deltas.supply.scaledP2PTotal = totalP2PSupply;
        deltas.borrow.scaledP2PTotal = totalP2PBorrow;
        deltas.supply.scaledDelta = supplyDelta;

        uint256 expectedFee = totalP2PBorrow.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            totalP2PSupply.rayMul(indexes.supply.p2pIndex).zeroFloorSub(supplyDelta.rayMul(indexes.supply.poolIndex))
        );
        expectedFee = Math.min(amount, expectedFee);
        uint256 toProcess = DeltasLib.repayFee(deltas, amount, indexes);
        assertEq(toProcess, amount - expectedFee, "expected fee");
        assertEq(deltas.supply.scaledP2PTotal, totalP2PSupply, "supply total");
        assertEq(
            deltas.borrow.scaledP2PTotal,
            totalP2PBorrow.zeroFloorSub(expectedFee.rayDivDown(indexes.borrow.p2pIndex)),
            "borrow total"
        );
    }
}
