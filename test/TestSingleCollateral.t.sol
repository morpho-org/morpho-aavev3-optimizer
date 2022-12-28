// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./TestGas.sol";

contract TestSingleCollateral is TestGas {
    function setUp() public override {
        super.setUp();

        collat(aDai, 1 ether);
    }

    function test() public view {
        _liquidityData(user, aDai, 0, 0);
    }
}
