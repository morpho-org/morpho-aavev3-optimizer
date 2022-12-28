// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./TestGas.sol";

contract TestSupplyBorrowAllMarkets is TestGas {
    function setUp() public override {
        super.setUp();

        supply(aDai, 0.5e18, 0.5e18);
        borrow(aDai, 0.25e18, 0.25e18);

        supply(aAave, 0.5e18, 0.5e18);
        borrow(aAave, 0.25e18, 0.25e18);

        supply(aWeth, 0.5e18, 0.5e18);
        borrow(aWeth, 0.25e18, 0.25e18);

        supply(aWbtc, 0.5e8, 0.5e8);
        borrow(aWbtc, 0.25e8, 0.25e8);

        supply(aUsdt, 0.5e8, 0.5e8);
        borrow(aUsdt, 0.25e8, 0.25e8);

        supply(aUsdc, 0.5e6, 0.5e6);
        borrow(aUsdc, 0.25e6, 0.25e6);
    }

    function test() public view {
        _liquidityData(user, aDai, 0, 0);
    }
}
