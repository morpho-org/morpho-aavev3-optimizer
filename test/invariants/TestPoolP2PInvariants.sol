// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";

import {PoolP2PHandler} from "../handlers/PoolP2PHandler.sol";

import "../helpers/IntegrationTest.sol";

contract TestPoolP2PInvariants is Test{

    PoolP2PHandler public handler;

    function setUp() public{

        handler = new PoolP2PHandler();
        handler.setUp();

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.supply.selector;
        selectors[1] = handler.borrow.selector;
        selectors[2] = handler.withdraw.selector;
        selectors[3] = handler.repay.selector;
        selectors[4] = handler.supply_collateral.selector;
        selectors[5] = handler.withdraw_collateral.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));

        targetContract(address(handler));
    }


    function invariant_Pool_Supply() public {
        assertTrue(handler.S_Pool()==handler.Sum_Supply_Pool());
    }

    function invariant_P2P_Supply() public {
        assertTrue(handler.S_P2P()==handler.Sum_Supply_P2P());
    }

    function invariant_Pool_Borrow() public {
        assertTrue(handler.B_Pool()==handler.Sum_Borrow_Pool());
    }
    
    function invariant_P2P_Borrow() public {
        assertTrue(handler.B_P2P()==handler.Sum_Borrow_P2P());
    }

    function invariant_Equal_Amount_P2P() public {
        assertTrue(handler.Sum_Supply_P2P_minus_Delta_S()==handler.Sum_Borrow_P2P_minus_Delta_B());
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }


}
