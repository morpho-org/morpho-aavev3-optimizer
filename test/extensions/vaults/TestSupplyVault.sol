// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/extensions/vaults/TestSetupVaults.sol";

contract TestSupplyVault is TestSetupVaults {
    using WadRayMath for uint256;

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
        assertEq(usdcSupplyVault.decimals(), 18);
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
        user.withdrawVault(daiSupplyVault, amount);

        uint256 totalBalance = morpho.supplyBalance(dai, address(daiSupplyVault));

        assertApproxEqAbs(daiSupplyVault.balanceOf(address(user)), 0, 1, "mcDAI balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
    }

    function testShouldWithdrawAllUsdcAmount(uint256 amount) public {
        amount = _boundSupply(testMarkets[usdc], amount);

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(usdc);
        uint256 expectedOnPool = amount.rayDiv(poolSupplyIndex);

        user.depositVault(usdcSupplyVault, amount);
        user.withdrawVault(usdcSupplyVault, expectedOnPool.rayMul(poolSupplyIndex));

        uint256 totalBalance = morpho.supplyBalance(address(usdc), address(usdcSupplyVault));

        assertApproxEqAbs(usdcSupplyVault.balanceOf(address(user)), 0, 1, "mcUSDT balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
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

    function testShouldClaimRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balanceBefore = user.balanceOf(rewardToken);

        (address[] memory rewardTokens, uint256[] memory claimedAmounts) = daiSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens.length, 1);
        assertEq(rewardTokens[0], rewardToken);
        assertEq(claimedAmounts.length, 1);

        uint256 balanceAfter = user.balanceOf(rewardToken);

        assertGt(claimedAmounts[0], 0);
        assertApproxEqAbs(
            ERC20(rewardToken).balanceOf(address(daiSupplyVault)), 0, 1, "non zero rewardToken balance on vault"
        );
        assertEq(balanceAfter, balanceBefore + claimedAmounts[0], "unexpected rewardToken balance");
    }

    function testShouldClaimTwiceRewardsWhenDepositedForSameAmountAndTwiceDuration(uint256 amount, uint256 timePassed)
        public
    {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        promoter1.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) = daiSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            daiSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        assertApproxEqAbs(
            expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0], 1, "unexpected total rewards amount"
        );
        assertLe(claimedAmounts1[0] + claimedAmounts2[0], expectedTotalRewardsAmount);
        assertApproxEqAbs(claimedAmounts1[0], 2 * claimedAmounts2[0], 1, "unexpected rewards amount"); // not exact because of rounded interests
    }

    function testShouldClaimSameRewardsWhenDepositedAtSameTime(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        uint256 shares1 = user.depositVault(daiSupplyVault, amount);
        uint256 shares2 = promoter1.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        user.redeemVault(daiSupplyVault, shares1 / 2);
        promoter1.redeemVault(daiSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        user.redeemVault(daiSupplyVault, shares1 / 2);
        promoter1.redeemVault(daiSupplyVault, shares2 / 2);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) = daiSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            daiSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        assertApproxEqAbs(
            expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0], 1, "unexpected total rewards amount"
        );
        assertGe(expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0]);
        assertApproxEqAbs(claimedAmounts1[0], claimedAmounts2[0], 1, "unexpected rewards amount"); // not exact because of rewardTokenounded interests
    }

    function testShouldClaimSameRewardsWhenDepositedForSameAmountAndDuration1(uint256 amount, uint256 timePassed)
        public
    {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        uint256 shares1 = user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        uint256 shares2 = promoter1.depositVault(daiSupplyVault, amount);
        user.redeemVault(daiSupplyVault, shares1 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        user.redeemVault(daiSupplyVault, shares1 / 2);
        promoter1.redeemVault(daiSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) = daiSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            daiSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        assertApproxEqAbs(
            expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0], 1e5, "unexpected total rewards amount"
        );
        assertGe(expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0]);
        assertApproxEqAbs(claimedAmounts1[0], claimedAmounts2[0], 1, "unexpected rewards amount"); // not exact because of rewardTokenounded interests
    }

    function testShouldClaimSameRewardsWhenDepositedForSameAmountAndDuration2(uint256 amount, uint256 timePassed)
        public
    {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        uint256 shares1 = user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        uint256 shares2 = promoter1.depositVault(daiSupplyVault, amount);
        user.redeemVault(daiSupplyVault, shares1 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        uint256 shares3 = promoter2.depositVault(daiSupplyVault, amount);
        user.redeemVault(daiSupplyVault, shares1 / 2);
        promoter1.redeemVault(daiSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        promoter1.redeemVault(daiSupplyVault, shares2 / 2);
        promoter2.redeemVault(daiSupplyVault, shares3 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount += rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        promoter2.redeemVault(daiSupplyVault, shares3 / 2);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) = daiSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            daiSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        (address[] memory rewardTokens3, uint256[] memory claimedAmounts3) =
            daiSupplyVault.claimRewards(address(promoter2));

        assertEq(rewardTokens3.length, 1);
        assertEq(rewardTokens3[0], rewardToken);
        assertEq(claimedAmounts3.length, 1);

        assertApproxEqAbs(
            expectedTotalRewardsAmount,
            claimedAmounts1[0] + claimedAmounts2[0] + claimedAmounts3[0],
            1e5,
            "unexpected total rewards amount"
        );
        assertGe(expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0] + claimedAmounts3[0]);
        assertApproxEqAbs(
            ERC20(rewardToken).balanceOf(address(daiSupplyVault)), 0, 1, "non zero rewardToken balance on vault"
        );
        assertApproxEqAbs(claimedAmounts1[0], claimedAmounts2[0], 1, "unexpected rewards amount 1-2"); // not exact because of rewardTokenounded interests
        assertApproxEqAbs(claimedAmounts2[0], claimedAmounts3[0], 1, "unexpected rewards amount 2-3"); // not exact because of rewardTokenounded interests
    }

    function testRewardsShouldAccrueWhenDepositingOnBehalf(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        promoter1.depositVault(daiSupplyVault, amount, address(user));
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        // Should update the unclaimed amount
        promoter1.depositVault(daiSupplyVault, amount, address(user));
        uint256 userReward1_1 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        vm.warp(block.timestamp + timePassed);
        uint256 userReward1_2 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        uint256 userReward2 = daiSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);
        assertEq(userReward2, 0);
        assertGt(userReward1_1, 0);
        assertGt(userReward1_2, 0);
        assertApproxEqAbs(userReward1_1, expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(userReward1_1 * 3, userReward1_2, userReward1_2 / 1000);
    }

    function testRewardsShouldAccrueWhenMintingOnBehalf(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        promoter1.mintVault(daiSupplyVault, daiSupplyVault.previewMint(amount), address(user));
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        // Should update the unclaimed amount
        promoter1.mintVault(daiSupplyVault, daiSupplyVault.previewMint(amount), address(user));

        uint256 userReward1_1 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        vm.warp(block.timestamp + timePassed);
        uint256 userReward1_2 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        uint256 userReward2 = daiSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);
        assertEq(userReward2, 0);
        assertGt(userReward1_1, 0);
        assertApproxEqAbs(userReward1_1, expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(userReward1_1 * 3, userReward1_2, userReward1_2 / 1000);
    }

    function testRewardsShouldAccrueWhenRedeemingToReceiver(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        user.depositVault(daiSupplyVault, amount);
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        // Should update the unclaimed amount
        user.redeemVault(daiSupplyVault, daiSupplyVault.balanceOf(address(user)), address(promoter1), address(user));
        (, uint128 userReward1_1) = daiSupplyVault.userRewards(rewardToken, address(user));

        vm.warp(block.timestamp + timePassed);

        uint256 userReward1_2 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 userReward2 = daiSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        (uint128 index2,) = daiSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, 0);
        assertEq(userReward2, 0);
        assertGt(uint256(userReward1_1), 0);
        assertApproxEqAbs(uint256(userReward1_1), expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(uint256(userReward1_1), userReward1_2, 1);
    }

    function testRewardsShouldAccrueWhenWithdrawingToReceiver(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = dai;

        user.depositVault(daiSupplyVault, amount);
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(daiSupplyVault), rewardToken);

        // Should update the unclaimed amount
        user.withdrawVault(daiSupplyVault, daiSupplyVault.maxWithdraw(address(user)), address(promoter1), address(user));

        (, uint128 userReward1_1) = daiSupplyVault.userRewards(rewardToken, address(user));

        vm.warp(block.timestamp + timePassed);

        uint256 userReward1_2 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 userReward2 = daiSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        (uint128 index2,) = daiSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, 0);
        assertEq(userReward2, 0);
        assertGt(uint256(userReward1_1), 0);
        assertApproxEqAbs(uint256(userReward1_1), expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(uint256(userReward1_1), userReward1_2, 1);
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

    function testTransferAccrueRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = daiSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        daiSupplyVault.transfer(address(promoter1), balance);

        uint256 rewardAmount = ERC20(rewardToken).balanceOf(address(daiSupplyVault));
        assertGt(rewardAmount, 0);

        uint256 expectedIndex = rewardAmount.rayDiv(daiSupplyVault.totalSupply());
        uint256 rewardsIndex = daiSupplyVault.rewardsIndex(rewardToken);
        assertEq(expectedIndex, rewardsIndex);

        (uint256 index1, uint256 unclaimed1) = daiSupplyVault.userRewards(rewardToken, address(user));
        assertEq(index1, rewardsIndex);
        assertEq(unclaimed1, rewardAmount);

        (uint256 index2, uint256 unclaimed2) = daiSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, rewardsIndex);
        assertEq(unclaimed2, 0);

        (, uint256[] memory rewardsAmount1) = daiSupplyVault.claimRewards(address(user));
        (, uint256[] memory rewardsAmount2) = daiSupplyVault.claimRewards(address(promoter1));
        assertGt(rewardsAmount1[0], 0, "rewardsAmount1");
        assertEq(rewardsAmount2[0], 0);
    }

    function testTransferFromAccrueRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = daiSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        daiSupplyVault.approve(address(promoter2), balance);

        vm.prank(address(promoter2));
        daiSupplyVault.transferFrom(address(user), address(promoter1), balance);

        uint256 rewardAmount = ERC20(rewardToken).balanceOf(address(daiSupplyVault));
        assertGt(rewardAmount, 0);

        uint256 expectedIndex = rewardAmount.rayDiv(daiSupplyVault.totalSupply());
        uint256 rewardsIndex = daiSupplyVault.rewardsIndex(rewardToken);
        assertEq(rewardsIndex, expectedIndex);

        (uint256 index1, uint256 unclaimed1) = daiSupplyVault.userRewards(rewardToken, address(user));
        assertEq(index1, rewardsIndex);
        assertEq(unclaimed1, rewardAmount);

        (uint256 index2, uint256 unclaimed2) = daiSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, rewardsIndex);
        assertEq(unclaimed2, 0);

        (uint256 index3, uint256 unclaimed3) = daiSupplyVault.userRewards(rewardToken, address(promoter2));
        assertEq(index3, 0);
        assertEq(unclaimed3, 0);

        (, uint256[] memory rewardsAmount1) = daiSupplyVault.claimRewards(address(user));
        (, uint256[] memory rewardsAmount2) = daiSupplyVault.claimRewards(address(promoter1));
        (, uint256[] memory rewardsAmount3) = daiSupplyVault.claimRewards(address(promoter2));
        assertGt(rewardsAmount1[0], 0, "rewardsAmount1");
        assertEq(rewardsAmount2[0], 0);
        assertEq(rewardsAmount3[0], 0);
    }

    function testTransferAndClaimRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        promoter1.depositVault(daiSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = daiSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        daiSupplyVault.transfer(address(promoter1), balance);

        vm.warp(block.timestamp + timePassed);

        uint256 rewardsAmount1 = daiSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 rewardsAmount2 = daiSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        assertGt(rewardsAmount1, 0);
        assertApproxEqAbs(rewardsAmount1, (2 * rewardsAmount2) / 3, rewardsAmount1 / 100);
        // Why rewardsAmount1 is 2/3 of rewardsAmount2 can be explained as follows:
        // user first gets X rewards corresponding to amount over one period of time
        // user then and promoter1 get X rewards each (under the approximation that doubling the amount doubles the rewards)
        // promoter1 then gets 2 * X rewards
        // In the end, user got 2 * X rewards while promoter1 got 3 * X
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

        assertEq(assets, expectedOnPool.rayMul(pool.getReserveNormalizedIncome(dai)), "unexpected withdrawn assets");
    }

    function testShouldWithdrawAllAmountWhenMorphoPoolIndexesOutdated(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[dai], amount);
        timePassed = bound(timePassed, 1, 10 days);

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedIncome(dai));

        user.depositVault(daiSupplyVault, amount);

        vm.roll(block.number + (timePassed + 19) / 20);
        vm.warp(block.timestamp + timePassed);

        user.withdrawVault(daiSupplyVault, expectedOnPool.rayMul(pool.getReserveNormalizedIncome(dai)));

        uint256 totalBalance = morpho.supplyBalance(address(usdc), address(daiSupplyVault));

        assertEq(daiSupplyVault.balanceOf(address(user)), 0, "mcUSDT balance not zero");
        assertEq(totalBalance, 0, "totalBalance not zero");
    }
}
