// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestGas} from "./TestGas.sol";

contract TestRef is TestGas {
    function test() public view {
        _liquidityData(user, aDai, 0, 0);
    }
}
