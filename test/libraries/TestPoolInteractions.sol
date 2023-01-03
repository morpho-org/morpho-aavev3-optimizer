// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {IPool, IPoolAddressesProvider} from "../../src/interfaces/aave/IPool.sol";
import {IAToken} from "../../src/interfaces/aave/IAToken.sol";
import {PoolInteractions} from "../../src/libraries/PoolInteractions.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {TestSetup} from "../setup/TestSetup.sol";
import {ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {DataTypes} from "../../src/libraries/aave/DataTypes.sol";

contract TestPoolInteractions is TestSetup {
    using PoolInteractions for IPool;

    address aDai;
    address vDai;

    uint256 public constant MIN_AMOUNT = 10;
    uint256 public constant MAX_AMOUNT = 100 ether;

    function setUp() public virtual override {
        super.setUp();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(dai);
        aDai = reserveData.aTokenAddress;
        vDai = reserveData.variableDebtTokenAddress;
    }

    function testSupplyToPool(uint96 amount) public {
        vm.assume(amount > MIN_AMOUNT && amount < MAX_AMOUNT);
        ERC20(dai).approve(address(pool), type(uint256).max);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 aBalanceBefore = ERC20(aDai).balanceOf(address(this));

        pool.supplyToPool(dai, amount);

        assertEq(ERC20(dai).balanceOf(address(this)) + amount, balanceBefore, "balance");
        assertApproxEqAbs(ERC20(aDai).balanceOf(address(this)), aBalanceBefore + amount, 1, "aBalance");
    }

    function testSupplyRevertsWithZero() public {
        ERC20(dai).approve(address(pool), 100 ether);
        vm.expectRevert(bytes("26"));
        pool.supplyToPool(dai, 0);
    }

    function testWithdrawFromPool(uint96 amount) public {
        vm.assume(amount > MIN_AMOUNT && amount < MAX_AMOUNT);
        ERC20(dai).approve(address(pool), type(uint256).max);
        pool.supplyToPool(dai, MAX_AMOUNT);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 aBalanceBefore = ERC20(aDai).balanceOf(address(this));

        pool.withdrawFromPool(dai, aDai, amount / 2);

        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore + amount / 2, "balance");
        assertApproxEqAbs(ERC20(aDai).balanceOf(address(this)) + amount / 2, aBalanceBefore, 1, "aBalance");
    }

    function testBorrowFromPool(uint96 amount) public {
        vm.assume(amount > MIN_AMOUNT && amount < MAX_AMOUNT);
        ERC20(dai).approve(address(pool), type(uint256).max);
        pool.supplyToPool(dai, MAX_AMOUNT);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 vBalanceBefore = ERC20(vDai).balanceOf(address(this));

        pool.borrowFromPool(dai, amount / 2);

        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore + amount / 2, "balance");
        assertApproxEqAbs(ERC20(vDai).balanceOf(address(this)), vBalanceBefore + amount / 2, 1, "vBalance");
    }

    function testBorrowRevertsWithZero() public {
        ERC20(dai).approve(address(pool), 100 ether);
        pool.supplyToPool(dai, 100 ether);

        vm.expectRevert(bytes("26"));
        pool.borrowFromPool(dai, 0);
    }

    function testRepayToPool(uint96 amount) public {
        vm.assume(amount > MIN_AMOUNT && amount < MAX_AMOUNT);
        ERC20(dai).approve(address(pool), type(uint256).max);
        pool.supplyToPool(dai, MAX_AMOUNT);
        pool.borrowFromPool(dai, amount / 2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 vBalanceBefore = ERC20(vDai).balanceOf(address(this));

        pool.repayToPool(dai, amount / 4);

        assertEq(ERC20(dai).balanceOf(address(this)) + amount / 4, balanceBefore, "balance");
        assertApproxEqAbs(ERC20(vDai).balanceOf(address(this)) + amount / 4, vBalanceBefore, 1, "vBalance");
    }
}
