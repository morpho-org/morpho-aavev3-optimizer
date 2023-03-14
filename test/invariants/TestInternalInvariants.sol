// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@forge-std/Test.sol";

import {InternalHandler} from "../handlers/InternalHandler.sol";

import "../helpers/IntegrationTest.sol";

contract TestInternalInvariants is Test{

    InternalHandler public handler;

    function setUp() public{

        handler = new InternalHandler();
        handler.setUp();

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.supply.selector;
        selectors[1] = handler.supply_collateral.selector;
        selectors[2] = handler.borrow.selector;
        selectors[3] = handler.withdraw.selector;
        selectors[4] = handler.withdraw_collateral.selector;
        selectors[5] = handler.repay.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));

        targetContract(address(handler));
    }


    function invariant_Pool_Supply_internal() public {
        assertTrue(handler.S_Pool()==handler.Sum_Supply_Pool());
    }

    function invariant_Pool_Borrow_internal() public {
        assertTrue(handler.B_Pool()==handler.Sum_Borrow_Pool());
    }
    
    function invariant_P2P_Supply_internal() public {
        assertTrue(handler.S_P2P()==handler.Sum_Supply_P2P());
    }
    
    function invariant_P2P_Borrow_internal() public {
        assertTrue(handler.B_P2P()==handler.Sum_Borrow_P2P());
    }

    function invariant_Equal_Amount_P2P_internal() public {
        assertTrue(handler.Sum_Supply_P2P_minus_Delta_S()==handler.Sum_Borrow_P2P_minus_Delta_B());
    }

    function invariant_Morpho_Pool_Supply_internal() public {
        assertApproxEqAbs(handler.Sum_Supply_Pool_plus_Delta_S_plus_Collateralpos(),handler.Supply_Morpho(), 5);
    }

    function invariant_Morpho_Pool_Borrow_internal() public {
        assertApproxEqAbs(handler.Sum_Borrow_Pool_plus_Delta_B(), handler.Borrow_Morpho(), 5);
    }

}