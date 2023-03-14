// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {InvariantTest as ForgeInvariantTest} from "@forge-std/InvariantTest.sol";
import "test/helpers/IntegrationTest.sol";

contract InvariantTest is IntegrationTest, ForgeInvariantTest {
    function setUp() public virtual override {
        super.setUp();

        targetContract(address(this));
    }

    function _targetDefaultSenders() internal {
        targetSender(0x1000000000000000000000000000000000000000);
        targetSender(0x0100000000000000000000000000000000000000);
        targetSender(0x0010000000000000000000000000000000000000);
        targetSender(0x0001000000000000000000000000000000000000);
        targetSender(0x0000100000000000000000000000000000000000);
        targetSender(0x0000010000000000000000000000000000000000);
        targetSender(0x0000001000000000000000000000000000000000);
        targetSender(0x0000000100000000000000000000000000000000);
    }

    function _randomSender(address seed) internal view returns (address) {
        address[] memory senders = targetSenders();

        return senders[uint256(uint160(seed)) % senders.length];
    }
}
