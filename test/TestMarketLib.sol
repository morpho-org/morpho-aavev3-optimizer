// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {Types} from "../src/libraries/Types.sol";
import {MarketLib} from "../src/libraries/MarketLib.sol";

import {Test} from "@forge-std/Test.sol";

contract TestMarketLib is Test {
    using MarketLib for Types.Market;

    Types.Market public market;

    function testIsCreated() public {
        assertFalse(market.isCreated());
        market.aToken = address(1);
        assertTrue(market.isCreated());
    }

    function testSetAndGetIndexes() public {
        assertEq(market.indexes.poolSupplyIndex, 0);
        assertEq(market.indexes.poolBorrowIndex, 0);
        assertEq(market.indexes.p2pSupplyIndex, 0);
        assertEq(market.indexes.p2pBorrowIndex, 0);

        market.setIndexes(Types.Indexes256(1, 2, 3, 4));

        assertEq(market.indexes.poolSupplyIndex, 1);
        assertEq(market.indexes.poolBorrowIndex, 2);
        assertEq(market.indexes.p2pSupplyIndex, 3);
        assertEq(market.indexes.p2pBorrowIndex, 4);
    }
}
