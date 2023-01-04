// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {Test} from "@forge-std/Test.sol";
import {console2} from "@forge-std/console2.sol";

import {MorphoInternal} from "../src/MorphoInternal.sol";
import {Types} from "../src/libraries/Types.sol";

contract TestMorphoInternal is MorphoInternal, Test {
    uint256 public constant positionMax = uint256(type(Types.PositionType).max);

    function testDecodeId(uint256 id) public {
        vm.assume((id >> 252) <= positionMax);
        (address underlying, Types.PositionType positionType) = _decodeId(id);
        assertEq(underlying, address(uint160(id)));
        assertEq(uint256(positionType), id >> 252);
    }

    function testReverseDecodeId(address underlying, uint256 positionType) public {
        positionType = positionType % (positionMax + 1);
        uint256 id = uint256(uint160(underlying)) + (positionType << 252);
        (address decodedUnderlying, Types.PositionType decodedPositionType) = _decodeId(id);
        assertEq(decodedUnderlying, underlying);
        assertEq(uint256(decodedPositionType), positionType);
    }
}
