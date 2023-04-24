// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/extensions/vaults/TestSetupVaults.sol";

contract TestSupplyVaultNoRewards is TestSetupVaults {
    using WadRayMath for uint256;

    function setUp() public virtual override {
        super.setUp();
    }

    function testCorrectInitialisationDai() public {
        assertEq(daiSupplyVault.owner(), address(this));
        assertEq(daiSupplyVault.name(), "MorphoAaveDAI");
        assertEq(daiSupplyVault.symbol(), "maDAI");
        assertEq(daiSupplyVault.underlying(), dai);
        assertEq(daiSupplyVault.asset(), dai);
        assertEq(daiSupplyVault.decimals(), 18);
    }

    function testCorrectInitialisationUsdc() public {
        assertEq(usdcSupplyVault.owner(), address(this));
        assertEq(usdcSupplyVault.name(), "MorphoAaveUSDC");
        assertEq(usdcSupplyVault.symbol(), "maUSDC");
        assertEq(usdcSupplyVault.underlying(), usdc);
        assertEq(usdcSupplyVault.asset(), usdc);
        assertEq(usdcSupplyVault.decimals(), 6);
    }

    function testShouldDepositAmount(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        user.depositVault(daiSupplyVault, amount);

        (uint256 totalBalance) = morpho.supplyBalance(dai, address(daiSupplyVault));

        assertGt(daiSupplyVault.balanceOf(address(user)), 0, "mcDAI balance is zero");
        assertApproxEqAbs(totalBalance, amount, 2, "totalBalance");
    }

    function testShouldWithdrawAllAmount(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        user.depositVault(daiSupplyVault, amount);
        user.withdrawVault(daiSupplyVault, daiSupplyVault.maxWithdraw(address(user)));

        uint256 totalBalance = morpho.supplyBalance(dai, address(daiSupplyVault));

        assertApproxEqAbs(daiSupplyVault.balanceOf(address(user)), 0, 1, "mcDAI balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
    }

    function testShouldWithdrawAllUsdcAmount(uint256 amount) public {
        amount = _boundSupply(testMarkets[usdc], amount);

        user.depositVault(usdcSupplyVault, amount);

        uint256 balanceBefore = ERC20(usdc).balanceOf(address(user));
        user.withdrawVault(usdcSupplyVault, usdcSupplyVault.maxWithdraw(address(user)));

        uint256 totalBalance = morpho.supplyBalance(address(usdc), address(usdcSupplyVault));

        assertApproxEqAbs(usdcSupplyVault.balanceOf(address(user)), 0, 1, "mcUSDT balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
        assertApproxEqAbs(ERC20(usdc).balanceOf(address(user)) - balanceBefore, amount, 2, "expectedWithdraw");
    }

    function testShouldWithdrawAllShares(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        uint256 shares = user.depositVault(daiSupplyVault, amount);
        user.redeemVault(daiSupplyVault, shares); // cannot withdraw amount because of Compound rounding errors

        uint256 totalBalance = morpho.supplyBalance(dai, address(daiSupplyVault));

        assertEq(daiSupplyVault.balanceOf(address(user)), 0, "mcDAI balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
    }

    function testShouldNotWithdrawWhenNotDeposited(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        uint256 shares = user.depositVault(daiSupplyVault, amount);

        vm.expectRevert("ERC4626: redeem more than max");
        promoter1.redeemVault(daiSupplyVault, shares);
    }

    function testShouldNotWithdrawOnBehalfIfNotAllowed(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        uint256 shares = user.depositVault(daiSupplyVault, amount);

        vm.expectRevert("ERC4626: redeem more than max");
        user.redeemVault(daiSupplyVault, shares, address(promoter1));
    }

    function testShouldWithdrawOnBehalfIfAllowed(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        uint256 shares = user.depositVault(daiSupplyVault, amount);

        user.approve(address(maDai), address(promoter1), shares);
        promoter1.redeemVault(daiSupplyVault, shares, address(user));
    }

    function testShouldNotMintZeroShare() public {
        vm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        user.mintVault(daiSupplyVault, 0);
    }

    function testShouldNotWithdrawGreaterAmount(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        user.depositVault(daiSupplyVault, amount);

        vm.expectRevert("ERC4626: withdraw more than max");
        user.withdrawVault(daiSupplyVault, amount * 2);
    }

    function testShouldNotRedeemMoreShares(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        uint256 shares = user.depositVault(daiSupplyVault, amount);

        vm.expectRevert("ERC4626: redeem more than max");
        user.redeemVault(daiSupplyVault, shares + 1);
    }

    function testTransfer(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        user.depositVault(daiSupplyVault, amount);

        uint256 balance = daiSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        daiSupplyVault.transfer(address(promoter1), balance);

        assertEq(daiSupplyVault.balanceOf(address(user)), 0);
        assertEq(daiSupplyVault.balanceOf(address(promoter1)), balance);
    }

    function testTransferFrom(uint256 amount) public {
        amount = _boundSupply(testMarkets[dai], amount);

        user.depositVault(daiSupplyVault, amount);

        uint256 balance = daiSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        daiSupplyVault.approve(address(promoter2), balance);

        vm.prank(address(promoter2));
        daiSupplyVault.transferFrom(address(user), address(promoter1), balance);

        assertEq(daiSupplyVault.balanceOf(address(user)), 0);
        assertEq(daiSupplyVault.balanceOf(address(promoter1)), balance);
    }

    function testShouldDepositCorrectAmountWhenMorphoPoolIndexesOutdated(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(daiSupplyVault, amount);

        vm.roll(block.number + (timePassed + 19) / 20);
        vm.warp(block.timestamp + 1_000_000);

        uint256 shares = promoter1.depositVault(daiSupplyVault, amount);
        uint256 assets = promoter1.redeemVault(daiSupplyVault, shares);

        assertApproxEqAbs(assets, amount, 1, "unexpected withdrawn assets");
    }

    function testShouldRedeemAllAmountWhenMorphoPoolIndexesOutdated(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedIncome(dai));

        uint256 shares = user.depositVault(daiSupplyVault, amount);

        vm.roll(block.number + (timePassed + 19) / 20);
        vm.warp(block.timestamp + timePassed);

        uint256 assets = user.redeemVault(daiSupplyVault, shares);

        assertApproxEqAbs(
            assets, expectedOnPool.rayMul(pool.getReserveNormalizedIncome(dai)), 2, "unexpected withdrawn assets"
        );
    }

    function testShouldWithdrawAllAmountWhenMorphoPoolIndexesOutdated(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        uint256 poolIndexBefore = pool.getReserveNormalizedIncome(dai);

        user.depositVault(daiSupplyVault, amount);

        vm.roll(block.number + (timePassed + 19) / 20);
        vm.warp(block.timestamp + timePassed);

        uint256 poolIndexAfter = pool.getReserveNormalizedIncome(dai);
        uint256 balanceBefore = ERC20(dai).balanceOf(address(user));

        user.withdrawVault(daiSupplyVault, daiSupplyVault.maxWithdraw(address(user)));

        uint256 totalBalance = morpho.supplyBalance(address(usdc), address(daiSupplyVault));

        assertEq(daiSupplyVault.balanceOf(address(user)), 0, "balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
        assertApproxEqAbs(
            ERC20(dai).balanceOf(address(user)) - balanceBefore,
            amount.rayDiv(poolIndexBefore).rayMul(poolIndexAfter),
            2,
            "unexpected withdrawn assets"
        );
    }
}
