// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {MorphoStorage} from "../src/MorphoStorage.sol";
import {MorphoGetters} from "../src/MorphoGetters.sol";

import "./setup/TestSetup.sol";

contract TestMorphoInternal is TestSetup, MorphoGetters {
    using TestConfig for TestConfig.Config;

    constructor() MorphoStorage(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function testIsManaging(address owner, address manager, bool isAllowed) public {
        _approveManager(owner, manager, isAllowed);
        assertEq(this.isManaging(owner, manager), isAllowed);
    }
}
