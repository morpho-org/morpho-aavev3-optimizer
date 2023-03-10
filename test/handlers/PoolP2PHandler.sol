// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UserMock} from "test/mocks/UserMock.sol";
import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DeltasLib} from "src/libraries/DeltasLib.sol";
import {console} from "forge-std/console.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@forge-std/console.sol";

import "../helpers/IntegrationTest.sol";

contract PoolP2PHandler is IntegrationTest{

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using DeltasLib for Types.Deltas;

    mapping(bytes32 => uint256) public calls;

    uint256 public S_P2P;
    uint256 public S_Pool;    
    uint256 public B_P2P;
    uint256 public B_Pool;
    uint256 public Morpho_Supply;
    address[] users;

    function setUp() public virtual override{
        super.setUp();
        
        users.push(address(0x0abc));
        users.push(address(0x0abd));
        users.push(address(0x0abe));
        users.push(address(0x0abf));
        users.push(address(0x0ac0));
    }


    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("supply", calls["supply"]);
        console.log("borrow", calls["borrow"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("repay", calls["repay"]);
    }


    function Sum_Supply_P2P() public view returns (uint256 Sum_P2P){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) 
                    Sum_P2P += morpho.scaledP2PSupplyBalance(underlyings[marketIndex], address(users[i]));
        
        return Sum_P2P;
    }

    function Sum_Supply_Pool() public view returns (uint256 Sum_Pool){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) 
                    Sum_Pool += morpho.scaledPoolSupplyBalance(underlyings[marketIndex],address(users[i]));
        
        return Sum_Pool;
    }

    function Sum_Borrow_P2P() public view returns (uint256 Sum_P2P){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) 
                    Sum_P2P += morpho.scaledP2PBorrowBalance(underlyings[marketIndex], address(users[i]));

        return Sum_P2P;
    }

    function Sum_Supply_P2P_minus_Delta_S() public view returns (uint256){
        uint256 Sum_P2P=Sum_Supply_P2P();
        uint256 delta_S;
        
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            delta_S += morpho.market(underlyings[marketIndex]).deltas.supply.scaledP2PTotal;
        }

        return Sum_P2P < delta_S ? 0 : Sum_P2P - delta_S;
    }

    function Sum_Borrow_P2P_minus_Delta_B() public view returns (uint256){
        uint256 Sum_P2P=Sum_Borrow_P2P();
        uint256 delta_B;
        
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            delta_B += morpho.market(underlyings[marketIndex]).deltas.borrow.scaledP2PTotal;
        }

        return Sum_P2P < delta_B ? 0 : Sum_P2P - delta_B;
    }

    function Sum_Borrow_Pool() public view returns (uint256 Sum_Pool){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) 
                    Sum_Pool += morpho.scaledPoolBorrowBalance(underlyings[marketIndex], address(users[i]));
        
        return Sum_Pool;
    }

    function current_balances(uint8 mindex) 
        public view 
        returns(uint256 supply_pool, uint256 supply_p2p, uint256 borrow_pool, uint256 borrow_p2p){
        for(uint i; i<users.length;i++){
            supply_pool += morpho.scaledPoolSupplyBalance(underlyings[mindex], address(users[i]));
            supply_p2p += morpho.scaledP2PSupplyBalance(underlyings[mindex], address(users[i]));
            borrow_pool += morpho.scaledPoolBorrowBalance(underlyings[mindex], address(users[i]));
            borrow_p2p += morpho.scaledP2PBorrowBalance(underlyings[mindex], address(users[i]));
        }
    }

    function increase_totals(uint256 supply_pool_delta, uint256 supply_p2p_delta, uint256 borrow_pool_delta, uint256 borrow_p2p_delta) public{
        S_Pool += supply_pool_delta;
        S_P2P += supply_p2p_delta;
        B_Pool += borrow_pool_delta;
        B_P2P += borrow_p2p_delta;
    }
    
    function decrease_totals(uint256 supply_pool_delta, uint256 supply_p2p_delta, uint256 borrow_pool_delta, uint256 borrow_p2p_delta) public{
        S_Pool -= supply_pool_delta;
        S_P2P -= supply_p2p_delta;
        B_Pool -= borrow_pool_delta;
        B_P2P -= borrow_p2p_delta;
    }

    function max_supply() internal view returns(uint64 max_s){
        uint256 ssp = Sum_Supply_Pool();
        max_s = ssp < type(uint64).max ? type(uint64).max-uint64(ssp) : 0;
    }

    function max_borrow(uint8 mindex, address user) internal view returns(uint64 max_b){
        uint256 psb = morpho.scaledPoolSupplyBalance(underlyings[mindex],address(user));
        max_b = psb < type(uint64).max ? uint64(psb) : type(uint64).max;
    }

    function max_withdraw(uint8 mindex, address user) internal view returns(uint64 max_w){
        uint256 psb = morpho.scaledPoolSupplyBalance(underlyings[mindex],address(user));
        uint256 p2psb = morpho.scaledP2PSupplyBalance(underlyings[mindex],address(user));

        max_w = psb + p2psb < type(uint64).max ? uint64(psb + p2psb) : type(uint64).max;
    }

    function max_repay(uint8 mindex, address user) internal view returns(uint64 max_r){
        uint256 pbb = morpho.scaledPoolBorrowBalance(underlyings[mindex],address(user));
        uint256 p2pbb = morpho.scaledP2PBorrowBalance(underlyings[mindex],address(user));
        max_r = pbb + p2pbb < type(uint64).max ? uint64(pbb + p2pbb) : type(uint64).max;
    }

    function supply(uint64 amount, uint8 mindex, uint8 sindex) public countCall("supply"){     
        sindex = uint8(bound(sindex, 0, users.length-1));
        address supplier = users[sindex];
        
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_supply()==0) return;

        amount = uint64(bound(amount, 1, max_supply()));
       
        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);
        
        vm.prank(address(user));
        ERC20(underlyings[mindex]).approve(address(morpho) , amount);
        user.supply(underlyings[mindex], amount, supplier);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function supply_collateral(uint64 amount, uint8 mindex, uint8 sindex) public countCall("supply"){     
        sindex = uint8(bound(sindex, 0, users.length-1));
        address supplier = users[sindex];
        
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_supply()==0) return;

        amount = uint64(bound(amount, 1, max_supply()));
       
        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);
        
        vm.prank(address(user));
        ERC20(underlyings[mindex]).approve(address(morpho) , amount);
        Morpho_Supply += user.supplyCollateral(underlyings[mindex], amount, supplier);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function borrow(uint64 amount, uint8 mindex, uint8 sindex) public countCall("borrow"){
        sindex = uint8(bound(sindex, 0, users.length-1));
        address borrower = users[sindex];
        
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_borrow(mindex, borrower)==0) return;
        if(!pool.getConfiguration(underlyings[mindex]).getBorrowingEnabled()) return;

        amount = uint64(bound(amount, 1, max_borrow(mindex, borrower)));     

        oracle.setAssetPrice(underlyings[mindex], 0);

        vm.prank(borrower);
        morpho.approveManager(address(user), true);

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);        

        vm.prank(address(user));
        user.borrow(underlyings[mindex], amount, borrower, address(user));

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function withdraw(uint64 amount, uint8 mindex, uint8 sindex) public countCall("withdraw"){
        sindex = uint8(bound(sindex, 0, users.length-1));
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_withdraw(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_withdraw(mindex, users[sindex])));

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);      

        user.withdraw(underlyings[mindex], amount);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function withdraw_collateral(uint64 amount, uint8 mindex, uint8 sindex) public countCall("withdraw"){
        sindex = uint8(bound(sindex, 0, users.length-1));        
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_withdraw(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_withdraw(mindex, users[sindex])));

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);      

        user.withdrawCollateral(underlyings[mindex], amount);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function repay(uint64 amount, uint8 mindex, uint8 sindex) public countCall("repay"){
        sindex = uint8(bound(sindex, 0, users.length-1));
        address repayer = users[sindex];
        
        mindex = uint8(bound(mindex, 0, underlyings.length-1));
        
        if(max_repay(mindex, repayer)==0) return;

        amount = uint64(bound(amount, 1, max_repay(mindex, repayer)));

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);      

        user.approve(underlyings[mindex], amount);
        user.repay(underlyings[mindex], amount, repayer);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }
}
