// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {InvariantHandler} from "test/helpers/InvariantHandler.sol";
import {InvariantTest} from "@forge-std/InvariantTest.sol";

contract TestInvariantMorpho is InvariantTest {
    InvariantHandler internal handler;

    function setUp() public {
        handler = new InvariantHandler();
        handler.setUp();

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.supply.selector;
        selectors[0] = handler.supplyCollateral.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetSender(0x1000000000000000000000000000000000000000);
        targetSender(0x0100000000000000000000000000000000000000);
        targetSender(0x0010000000000000000000000000000000000000);
        targetSender(0x0001000000000000000000000000000000000000);
        targetSender(0x0000100000000000000000000000000000000000);
        targetSender(0x0000010000000000000000000000000000000000);
        targetSender(0x0000001000000000000000000000000000000000);
        targetSender(0x0000000100000000000000000000000000000000);
    }

    function invariantSupply() public {}
}
