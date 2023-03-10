// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@forge-std/console.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20 as ERC20Permit2, Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {Types} from "src/libraries/Types.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "src/libraries/MarketBalanceLib.sol";

import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";
import "test/helpers/InternalTest.sol";


contract InternalHandler is InternalTest, PositionsManagerInternal {

    using PoolLib for IPool;
    using Permit2Lib for ERC20Permit2;    
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using SafeTransferLib for ERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address[] users;
    address actor;
    uint256 internal constant INITIAL_BALANCE = 3.5e38 ether;
    uint256 internal constant MAX_ITERATIONS = 100;


    uint256 public S_P2P;
    uint256 public S_Pool;    
    uint256 public B_P2P;
    uint256 public B_Pool;

    function setUp() public virtual override {
        super.setUp();

        _defaultIterations = Types.Iterations(10, 10);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            _createMarket(allUnderlyings[i], 0, 33_33);  
            DataTypes.ReserveConfigurationMap memory reserveConfig = pool.getConfiguration(allUnderlyings[i]);
            reserveConfig.setSupplyCap(0);            
            reserveConfig.setBorrowCap(0);            
            reserveConfig.setBorrowingEnabled(true);
            vm.prank(address(poolConfigurator));
            pool.setConfiguration(allUnderlyings[i], reserveConfig);   
        }

        _setBalances(address(this), 0);

        users.push(address(0x0aaa));
        users.push(address(0x0bbb));
        users.push(address(0x0ccc));
        actor = address(0x0f00);

        _setBalances(actor, INITIAL_BALANCE);
    }

    function max_supply() internal view returns(uint64 max_s){
        uint256 ssp = Sum_Supply_Pool();
        max_s = ssp < type(uint64).max ? type(uint64).max-uint64(ssp) : 0;
    }

    function max_borrow(uint8 mindex, address user) internal view returns(uint64 max_b){
        uint256 psb = _marketBalances[_marketsCreated[mindex]].scaledPoolSupplyBalance(user);
        max_b = psb < type(uint64).max ? uint64(psb) : type(uint64).max;
    }

    function max_withdraw(uint8 mindex, address user) internal view returns(uint64 max_w){
        uint256 psb = _marketBalances[_marketsCreated[mindex]].scaledPoolSupplyBalance(address(user));
        uint256 p2psb = _marketBalances[_marketsCreated[mindex]].scaledP2PSupplyBalance(address(user));

        max_w = psb + p2psb < type(uint64).max ? uint64(psb + p2psb) : type(uint64).max;
    }

    function max_repay(uint8 mindex, address user) internal view returns(uint64 max_r){
        uint256 pbb = _marketBalances[_marketsCreated[mindex]].scaledPoolBorrowBalance(address(user));
        uint256 p2pbb = _marketBalances[_marketsCreated[mindex]].scaledP2PBorrowBalance(address(user));
        max_r = pbb + p2pbb < type(uint64).max ? uint64(pbb + p2pbb) : type(uint64).max;
    }

    function Sum_Supply_Pool() public view returns (uint256 Sum_Pool){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) 
                    Sum_Pool += _marketBalances[_marketsCreated[marketIndex]].scaledPoolSupplyBalance(address(users[i]));
        
        return Sum_Pool;
    }

    function Sum_Borrow_Pool() public view returns (uint256 Sum_Pool){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) 
                    Sum_Pool += _marketBalances[_marketsCreated[marketIndex]].scaledPoolBorrowBalance(address(users[i]));
        
        return Sum_Pool;
    }

    function Sum_Borrow_P2P() public view returns (uint256 Sum_P2P){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) 
                    Sum_P2P += _marketBalances[_marketsCreated[marketIndex]].scaledP2PBorrowBalance(address(users[i]));

        return Sum_P2P;
    }
    
    function Sum_Supply_P2P() public view returns (uint256 Sum_P2P){
        for(uint i; i<users.length;i++)
                for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) 
                    Sum_P2P += _marketBalances[_marketsCreated[marketIndex]].scaledP2PSupplyBalance(address(users[i]));
        
        return Sum_P2P;
    }

    function Sum_Supply_P2P_minus_Delta_S() public view returns (uint256){
        uint256 Sum_P2P=Sum_Supply_P2P();
        uint256 delta_S;
        
        for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) {
            delta_S += _market[_marketsCreated[marketIndex]].deltas.supply.scaledP2PTotal;
        }

        return Sum_P2P < delta_S ? 0 : Sum_P2P - delta_S;
    }

    function Sum_Borrow_P2P_minus_Delta_B() public view returns (uint256){
        uint256 Sum_P2P=Sum_Borrow_P2P();
        uint256 delta_B;
        
        for (uint256 marketIndex; marketIndex < _marketsCreated.length; ++marketIndex) {
            delta_B += _market[_marketsCreated[marketIndex]].deltas.borrow.scaledP2PTotal;
        }

        return Sum_P2P < delta_B ? 0 : Sum_P2P - delta_B;
    }


    function current_balances(uint8 mindex) 
        public view 
        returns(uint256 supply_pool, uint256 supply_p2p, uint256 borrow_pool, uint256 borrow_p2p){
        for(uint i; i<users.length;i++){
            supply_pool += _marketBalances[_marketsCreated[mindex]].scaledPoolSupplyBalance(address(users[i]));
            supply_p2p += _marketBalances[_marketsCreated[mindex]].scaledP2PSupplyBalance(address(users[i]));
            borrow_pool += _marketBalances[_marketsCreated[mindex]].scaledPoolBorrowBalance(address(users[i]));
            borrow_p2p += _marketBalances[_marketsCreated[mindex]].scaledP2PBorrowBalance(address(users[i]));
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

    function supply(uint64 amount, uint8 mindex, uint8 sindex) public{     
        sindex = uint8(bound(sindex, 0, users.length-1));       
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_supply()==0) return;

        amount = uint64(bound(amount, 1, max_supply()));
        
        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);

        vm.prank(address(actor));
        ERC20(_marketsCreated[mindex]).approve(address(this) , amount);
        _supplyLogic(_marketsCreated[mindex], amount, actor, users[sindex]);
    
        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    }


    function supply_collateral(uint64 amount, uint8 mindex, uint8 sindex) public{     
        sindex = uint8(bound(sindex, 0, users.length-1));        
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_supply()==0) return;

        amount = uint64(bound(amount, 1, max_supply()));
        
        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);

        vm.prank(address(actor));
        ERC20(_marketsCreated[mindex]).approve(address(this) , amount);
        _supplyCollateralLogic(_marketsCreated[mindex], amount, actor, users[sindex]);
        
        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);

    }

    function borrow(uint64 amount, uint8 mindex, uint8 sindex) public{
        sindex = uint8(bound(sindex, 0, users.length-1));
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_borrow(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_borrow(mindex, users[sindex])));     

        oracle.setAssetPrice(_marketsCreated[mindex], 0);

        _approveManager(address(actor), msg.sender, true);

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);    

        _borrowLogic(_marketsCreated[mindex], amount, address(actor), users[sindex], MAX_ITERATIONS);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);

    }

    function withdraw(uint64 amount, uint8 mindex, uint8 sindex) public{
        sindex = uint8(bound(sindex, 0, users.length-1));
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_withdraw(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_withdraw(mindex, users[sindex])));

        _approveManager(address(actor), msg.sender, true);

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);    

        _withdrawLogic(_marketsCreated[mindex], amount, address(actor), users[sindex], MAX_ITERATIONS);
            
        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    }

    function withdraw_collateral(uint64 amount, uint8 mindex, uint8 sindex) public{
        sindex = uint8(bound(sindex, 0, users.length-1));        
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_withdraw(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_withdraw(mindex, users[sindex])));

        _approveManager(address(actor), msg.sender, true);

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);      

        _withdrawCollateralLogic(_marketsCreated[mindex], amount, address(actor), users[sindex]);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function repay(uint64 amount, uint8 mindex, uint8 sindex) public{
        sindex = uint8(bound(sindex, 0, users.length-1));
        mindex = uint8(bound(mindex, 0, _marketsCreated.length-1));
        
        if(max_repay(mindex, users[sindex])==0) return;

        amount = uint64(bound(amount, 1, max_repay(mindex, users[sindex])));

        (uint256 s_pool_before, uint256 s_p2p_before, uint256 b_pool_before, uint256 b_p2p_before) = current_balances(mindex);
        decrease_totals(s_pool_before, s_p2p_before, b_pool_before, b_p2p_before);      

        vm.prank(address(actor));
        ERC20(_marketsCreated[mindex]).approve(address(this) , amount);
        _repayLogic(_marketsCreated[mindex], amount, address(actor), users[sindex]);

        (uint256 s_pool_after, uint256 s_p2p_after, uint256 b_pool_after, uint256 b_p2p_after) = current_balances(mindex);
        increase_totals(s_pool_after, s_p2p_after, b_pool_after, b_p2p_after);
    
    }

    function _supplyLogic(address underlying, uint256 amount, address from, address onBehalf)
        internal
    {
        Types.Market storage market = _validateSupply(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        ERC20Permit2(underlying).transferFrom2(from, address(this), amount);

        Types.SupplyRepayVars memory vars = _executeSupply(underlying, amount, from, onBehalf, MAX_ITERATIONS, indexes);

        pool.repayToPool(underlying, market.variableDebtToken, vars.toRepay);
        pool.supplyToPool(underlying, vars.toSupply);

    }

    function _supplyCollateralLogic(address underlying, uint256 amount, address from, address onBehalf)
        internal
    {
        _validateSupplyCollateral(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        
        ERC20Permit2(underlying).transferFrom2(from, address(this), amount);
        
        _executeSupplyCollateral(underlying, amount, from, onBehalf, indexes.supply.poolIndex);
        
        pool.supplyToPool(underlying, amount);

    }

    function _borrowLogic(address underlying, uint256 amount, address borrower, address receiver, uint256 maxIterations)
        internal
    {
        Types.Market storage market = _validateBorrow(underlying, amount, borrower, receiver);
        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        _authorizeBorrow(underlying, amount, indexes);

        Types.BorrowWithdrawVars memory vars = _executeBorrow(underlying, amount, borrower, receiver, maxIterations, indexes);

        Types.LiquidityData memory values = _liquidityData(borrower);
        if (values.debt > values.borrowable) revert Errors.UnauthorizedBorrow();

        pool.withdrawFromPool(underlying, market.aToken, vars.toWithdraw);
        pool.borrowFromPool(underlying, vars.toBorrow);

        ERC20(underlying).safeTransfer(receiver, amount);

    }

    function _withdrawLogic(address underlying, uint256 amount, address supplier, address receiver, uint256 maxIterations) 
        internal 
    {
        Types.Market storage market = _validateWithdraw(underlying, amount, supplier, receiver);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserSupplyBalanceFromIndexes(underlying, supplier, indexes), amount);

        if (amount == 0) return;

        Types.BorrowWithdrawVars memory vars = _executeWithdraw(
            underlying, amount, supplier, receiver, Math.max(_defaultIterations.withdraw, maxIterations), indexes
        );

        pool.withdrawFromPool(underlying, market.aToken, vars.toWithdraw);
        pool.borrowFromPool(underlying, vars.toBorrow);

        ERC20(underlying).safeTransfer(receiver, amount);

    }

    function _withdrawCollateralLogic(address underlying, uint256 amount, address supplier, address receiver)
        internal
    {
        Types.Market storage market = _validateWithdrawCollateral(underlying, amount, supplier, receiver);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        uint256 poolSupplyIndex = indexes.supply.poolIndex;
        amount = Math.min(_getUserCollateralBalanceFromIndex(underlying, supplier, poolSupplyIndex), amount);

        if (amount == 0) return;

        _executeWithdrawCollateral(underlying, amount, supplier, receiver, poolSupplyIndex);

        // The following check requires accounting to have been performed.
        if (_getUserHealthFactor(supplier) < Constants.DEFAULT_LIQUIDATION_THRESHOLD) {
            revert Errors.UnauthorizedWithdraw();
        }

        pool.withdrawFromPool(underlying, market.aToken, amount);

        ERC20(underlying).safeTransfer(receiver, amount);

    }

    function _repayLogic(address underlying, uint256 amount, address repayer, address onBehalf)
        internal
    {
        Types.Market storage market = _validateRepay(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserBorrowBalanceFromIndexes(underlying, onBehalf, indexes), amount);

        if (amount == 0) return ;

        ERC20Permit2(underlying).transferFrom2(repayer, address(this), amount);

        Types.SupplyRepayVars memory vars =
            _executeRepay(underlying, amount, repayer, onBehalf, _defaultIterations.repay, indexes);

        pool.repayToPool(underlying, market.variableDebtToken, vars.toRepay);
        pool.supplyToPool(underlying, vars.toSupply);

    }
}