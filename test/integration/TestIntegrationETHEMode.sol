// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IWETHGateway} from "src/interfaces/IWETHGateway.sol";

import {WETHGateway} from "src/extensions/WETHGateway.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationETHEMode is IntegrationTest {
    IWETHGateway internal wethGateway;

    function setUp() public override {
        super.setUp();

        wethGateway = new WETHGateway(address(morpho));
    }
}
