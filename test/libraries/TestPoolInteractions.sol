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

    function setUp() public virtual override {
        super.setUp();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(dai);
        aDai = reserveData.aTokenAddress;
        vDai = reserveData.variableDebtTokenAddress;
    }

    function testSupplyToPool() public {
        ERC20(dai).approve(address(pool), 100 ether);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 aBalanceBefore = ERC20(aDai).balanceOf(address(this));

        pool.supplyToPool(dai, 100 ether);

        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore - 100 ether);
        assertEq(ERC20(aDai).balanceOf(address(this)), aBalanceBefore + 100 ether);

        vm.expectRevert(bytes("26"));
        pool.supplyToPool(dai, 0);
    }

    function testWithdrawFromPool() public {
        ERC20(dai).approve(address(pool), 100 ether);
        pool.supplyToPool(dai, 100 ether);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 aBalanceBefore = ERC20(aDai).balanceOf(address(this));

        pool.withdrawFromPool(dai, aDai, 100 ether);

        assertEq(ERC20(aDai).balanceOf(address(this)), aBalanceBefore - 100 ether);
        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore + 100 ether);
    }

    function testBorrowFromPool() public {
        ERC20(dai).approve(address(pool), 100 ether);
        pool.supplyToPool(dai, 100 ether);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 vBalanceBefore = ERC20(vDai).balanceOf(address(this));

        pool.borrowFromPool(dai, 50 ether);

        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore + 50 ether);
        assertEq(ERC20(vDai).balanceOf(address(this)), vBalanceBefore + 50 ether);

        vm.expectRevert(bytes("26"));
        pool.borrowFromPool(dai, 0);
    }

    function testRepayToPool() public {
        ERC20(dai).approve(address(pool), 100 ether);
        pool.supplyToPool(dai, 100 ether);
        pool.borrowFromPool(dai, 50 ether);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        uint256 vBalanceBefore = ERC20(vDai).balanceOf(address(this));

        ERC20(dai).approve(address(pool), 50 ether);
        pool.repayToPool(dai, 50 ether);

        assertEq(ERC20(dai).balanceOf(address(this)), balanceBefore - 50 ether);
        assertEq(ERC20(vDai).balanceOf(address(this)), vBalanceBefore - 50 ether);
    }
}
