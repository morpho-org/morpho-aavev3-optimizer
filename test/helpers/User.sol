// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../../src/interfaces/aave/IPool.sol";

import "../../src/Morpho.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

contract User {
    using SafeTransferLib for ERC20;

    Morpho internal morpho;
    IPool internal pool;

    uint256 internal constant DEFAULT_MAX_LOOPS = 10;

    constructor(Morpho _morpho) {
        setMorphoAddresses(_morpho);
    }

    receive() external payable {}

    function balanceOf(address token) external view returns (uint256) {
        return ERC20(token).balanceOf(address(this));
    }

    function approve(address token, uint256 amount) external {
        ERC20(token).safeApprove(address(morpho), amount);
    }

    function approve(address token, address spender, uint256 amount) external {
        ERC20(token).safeApprove(spender, amount);
    }

    function supply(address underlying, uint256 amount, address onBehalf) public {
        morpho.supply(underlying, amount, onBehalf, DEFAULT_MAX_LOOPS);
    }

    function supply(address underlying, uint256 amount, address onBehalf, uint256 maxLoops) public {
        morpho.supply(underlying, amount, onBehalf, maxLoops);
    }

    function supply(address underlying, uint256 amount) external {
        morpho.supply(underlying, amount, address(this), DEFAULT_MAX_LOOPS);
    }

    function supply(address underlying, uint256 amount, uint256 maxLoops) external {
        morpho.supply(underlying, amount, address(this), maxLoops);
    }

    function supplyCollateral(address underlying, uint256 amount) external {
        morpho.supplyCollateral(underlying, amount, address(this));
    }

    function supplyCollateral(address underlying, uint256 amount, address onBehalf) external {
        morpho.supplyCollateral(underlying, amount, onBehalf);
    }

    function borrow(address underlying, uint256 amount, address receiver, uint256 maxLoops) external {
        morpho.borrow(underlying, amount, receiver, maxLoops);
    }

    function borrow(address underlying, uint256 amount, address receiver) external {
        morpho.borrow(underlying, amount, receiver, DEFAULT_MAX_LOOPS);
    }

    function borrow(address underlying, uint256 amount, uint256 maxLoops) external {
        morpho.borrow(underlying, amount, address(this), maxLoops);
    }

    function borrow(address underlying, uint256 amount) external {
        morpho.borrow(underlying, amount, address(this), DEFAULT_MAX_LOOPS);
    }

    function repay(address underlying, uint256 amount, address onBehalf, uint256 maxLoops) external {
        morpho.repay(underlying, amount, onBehalf, maxLoops);
    }

    function repay(address underlying, uint256 amount, address onBehalf) external {
        morpho.repay(underlying, amount, onBehalf, DEFAULT_MAX_LOOPS);
    }

    function repay(address underlying, uint256 amount, uint256 maxLoops) external {
        morpho.repay(underlying, amount, address(this), maxLoops);
    }

    function repay(address underlying, uint256 amount) external {
        morpho.repay(underlying, amount, address(this), DEFAULT_MAX_LOOPS);
    }

    function withdraw(address underlying, uint256 amount, address receiver, uint256 maxLoops) external {
        morpho.withdraw(underlying, amount, receiver, maxLoops);
    }

    function withdraw(address underlying, uint256 amount, address receiver) external {
        morpho.withdraw(underlying, amount, receiver, DEFAULT_MAX_LOOPS);
    }

    function withdraw(address underlying, uint256 amount, uint256 maxLoops) external {
        morpho.withdraw(underlying, amount, address(this), maxLoops);
    }

    function withdraw(address underlying, uint256 amount) external {
        morpho.withdraw(underlying, amount, address(this), DEFAULT_MAX_LOOPS);
    }

    function withdrawCollateral(address underlying, uint256 amount, address receiver) external {
        morpho.withdrawCollateral(underlying, amount, receiver);
    }

    function withdrawCollateral(address underlying, uint256 amount) external {
        morpho.withdrawCollateral(underlying, amount, address(this));
    }

    function liquidate(address underlyingBorrowed, address underlyingCollateral, address borrower, uint256 amount)
        external
    {
        morpho.liquidate(underlyingBorrowed, underlyingCollateral, borrower, amount);
    }

    function setMorphoAddresses(Morpho _morpho) public {
        morpho = _morpho;
        pool = _morpho.pool();
    }
}
