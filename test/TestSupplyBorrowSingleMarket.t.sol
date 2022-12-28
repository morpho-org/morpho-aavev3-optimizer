// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./TestGas.sol";

contract TestSupplyBorrowSingleMarket is TestGas {
    function setUp() public override {
        super.setUp();

        supply(aDai, 0.5 ether, 0.5 ether);
        borrow(aDai, 0.25 ether, 0.25 ether);
    }

    function test() public view {
        _liquidityData(user, aDai, 0, 0);
    }
}
