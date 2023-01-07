// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Morpho} from "../src/Morpho.sol";

import "./setup/TestSetup.sol";

contract TestMorpho is TestSetup, Morpho {
    using TestConfig for TestConfig.Config;

    constructor() Morpho(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function testApproveManager(address owner, address manager, bool isAllowed) public {
        vm.prank(owner);
        this.approveManager(manager, isAllowed);
        assertEq(this.isManaging(owner, manager), isAllowed);
    }
}
