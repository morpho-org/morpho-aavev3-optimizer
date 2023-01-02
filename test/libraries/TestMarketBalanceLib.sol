// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {Types} from "../../src/libraries/Types.sol";
import {MarketBalanceLib} from "../../src/libraries/MarketBalanceLib.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

import {Test} from "@forge-std/Test.sol";

contract TestMarketLib is Test {
    using MarketBalanceLib for Types.MarketBalances;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    Types.MarketBalances internal marketBalances;

    function setUp() public {
        marketBalances.poolSuppliers.update(address(1), 0, 1, 20);
        marketBalances.p2pSuppliers.update(address(2), 0, 2, 20);
        marketBalances.poolBorrowers.update(address(3), 0, 3, 20);
        marketBalances.p2pBorrowers.update(address(4), 0, 4, 20);
        marketBalances.collateral[address(5)] = 5;
    }

    function testScaledPoolSupplyBalance() public {
        assertEq(marketBalances.scaledPoolSupplyBalance(address(0)), 0);
        assertEq(marketBalances.scaledPoolSupplyBalance(address(1)), 1);
    }

    function testScaledP2PSupplyBalance() public {
        assertEq(marketBalances.scaledP2PSupplyBalance(address(0)), 0);
        assertEq(marketBalances.scaledP2PSupplyBalance(address(2)), 2);
    }

    function testScaledPoolBorrowBalance() public {
        assertEq(marketBalances.scaledPoolBorrowBalance(address(0)), 0);
        assertEq(marketBalances.scaledPoolBorrowBalance(address(3)), 3);
    }

    function testScaledP2PBorrowBalance() public {
        assertEq(marketBalances.scaledP2PBorrowBalance(address(0)), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(address(4)), 4);
    }

    function testScaledCollateralBalance() public {
        assertEq(marketBalances.scaledCollateralBalance(address(0)), 0);
        assertEq(marketBalances.scaledCollateralBalance(address(5)), 5);
    }
}
