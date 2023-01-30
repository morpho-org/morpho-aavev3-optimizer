// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MorphoGetters} from "src/MorphoGetters.sol";

import "test/helpers/InternalTest.sol";

contract TestUnitMorphoGetters is InternalTest, MorphoGetters {
    function testGetStorageAt(bytes32 slot, bytes32 data) public {
        vm.store(address(this), slot, data);

        assertEq(this.getStorageAt(slot), data);
    }
}
