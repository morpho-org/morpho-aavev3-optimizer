// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/extensions/WETHGateway.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWETHGateway is IntegrationTest {
    uint256 internal constant MIN_AMOUNT = 1e9;
    uint256 internal constant MAX_ITERATIONS = 10;

    WETHGateway internal wethGateway;

    function setUp() public override {
        super.setUp();
        wethGateway = new WETHGateway(address(morpho));

        vm.label(address(wethGateway), "WETHGateway");
    }

    function testWETHAllowance() public {
        assertEq(ERC20(weth).allowance(address(wethGateway), address(morpho)), type(uint256).max);
    }

    function testCannotSendETHToWETHGateway(uint256 amount) public {
        deal(address(this), amount);
        vm.expectRevert(abi.encodeWithSelector(WETHGateway.OnlyWETH.selector));
        payable(address(wethGateway)).transfer(amount);
    }

    function testSupplyETH(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        assertEq(morpho.supplyBalance(weth, onBehalf), 0);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        uint256 balanceBefore = onBehalf.balance;
        _supplyETH(onBehalf, amount);

        assertEq(onBehalf.balance, balanceBefore);
        assertEq(address(this).balance, 0);
        assertGt(morpho.supplyBalance(weth, onBehalf), 0);
        assertEq(morpho.supplyBalance(weth, onBehalf), amount);
    }

    function testSupplyCollateralETH(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        assertEq(morpho.collateralBalance(weth, onBehalf), 0);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        uint256 balanceBefore = onBehalf.balance;
        _supplyCollateralETH(onBehalf, amount);

        assertEq(onBehalf.balance, balanceBefore);
        assertEq(address(this).balance, 0);
        assertGt(morpho.collateralBalance(weth, onBehalf), 0);
        assertApproxEqAbs(morpho.collateralBalance(weth, onBehalf), amount, 1);
    }

    function testCannotWithdrawIfWETHGatewayNotApproved(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        deal(address(this), amount);

        _supplyETH(address(this), amount);

        vm.expectRevert();
        wethGateway.withdrawETH(amount, address(this), MAX_ITERATIONS);
    }

    function testShouldWithdrawIfWETHGatewayApproved(uint256 amount, address receiver) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        console.log("bal0", address(this).balance);
        deal(address(this), amount);
        console.log("bal1", address(this).balance);

        _supplyETH(address(this), amount);
        assertGt(morpho.supplyBalance(weth, address(this)), 0);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 toWithdraw = bound(amount, 1, amount);
        wethGateway.withdrawETH(toWithdraw, receiver, MAX_ITERATIONS);

        if (receiver != address(this)) assertEq(address(this).balance, 0);
        assertEq(morpho.supplyBalance(weth, address(this)), amount - toWithdraw);
        assertApproxEqAbs(receiver.balance, balanceBefore + toWithdraw, 1);
    }

    function testCannotWithdrawCollateralIfWETHGatewayNotApproved(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        vm.expectRevert();
        wethGateway.withdrawCollateralETH(amount, address(this));
    }

    function testShouldWithdrawCollateralIfWETHGatewayApproved(uint256 amount, address receiver) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);
        assertGt(morpho.collateralBalance(weth, address(this)), 0);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 toWithdraw = bound(amount, 1, amount);
        wethGateway.withdrawCollateralETH(toWithdraw, receiver);

        if (receiver != address(this)) assertEq(address(this).balance, 0);
        assertEq(morpho.collateralBalance(weth, address(this)), amount - toWithdraw);
        assertApproxEqAbs(receiver.balance, balanceBefore + toWithdraw, 1);
    }

    function testCannotBorrowIfWETHGatewayNotApproved(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);
        assertGt(morpho.collateralBalance(weth, address(this)), 0);

        vm.expectRevert();
        wethGateway.borrowETH(amount / 2, address(this), MAX_ITERATIONS);
    }

    function testShouldBorrowIfWETHGatewayApproved(uint256 amount, address receiver) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);
        assertGt(morpho.collateralBalance(weth, address(this)), 0);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 toBorrow = amount / 2;
        wethGateway.borrowETH(toBorrow, receiver, MAX_ITERATIONS);

        assertGt(morpho.borrowBalance(weth, address(this)), 0);
        assertApproxEqAbs(morpho.borrowBalance(weth, address(this)), toBorrow, 1);
        assertEq(receiver.balance, balanceBefore + toBorrow);
    }

    function testShouldRepayETH(uint256 amount, address onBehalf, address repayer) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);
        assertGt(morpho.collateralBalance(weth, address(this)), 0);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = onBehalf.balance;
        uint256 toBorrow = amount / 2;
        wethGateway.borrowETH(toBorrow, onBehalf, MAX_ITERATIONS);

        assertGt(morpho.borrowBalance(weth, address(this)), 0);
        assertApproxEqAbs(morpho.borrowBalance(weth, address(this)), toBorrow, 1);
        assertEq(onBehalf.balance, balanceBefore + toBorrow);

        uint256 toRepay = bound(toBorrow, 1, toBorrow);
        deal(repayer, toRepay);
        vm.prank(repayer);
        wethGateway.repayETH{value: toRepay}(address(this));

        assertEq(repayer.balance, 0);
        assertApproxEqAbs(morpho.borrowBalance(weth, address(this)), toBorrow - toRepay, 1);
    }

    function _supplyETH(address onBehalf, uint256 amount) internal {
        wethGateway.supplyETH{value: amount}(onBehalf, MAX_ITERATIONS);
    }

    function _supplyCollateralETH(address onBehalf, uint256 amount) internal {
        wethGateway.supplyCollateralETH{value: amount}(onBehalf);
    }

    receive() external payable {}
}
