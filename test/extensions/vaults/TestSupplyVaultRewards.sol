// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/extensions/vaults/TestSetupVaults.sol";

contract TestSupplyVaultRewards is TestSetupVaults {
    using WadRayMath for uint256;
    using TestConfigLib for TestConfig;

    address rewardToken;

    function setUp() public virtual override {
        rewardsController = IRewardsController(config.getRewardsController());
        super.setUp();
        morpho.setRewardsManager(address(rewardsManager));
        rewardToken = wNative;
        // Trigger initial index update in rewards manager
        for (uint256 i; i < allUnderlyings.length; i++) {
            uint256 amount = testMarkets[allUnderlyings[i]].minAmount;
            ERC20(allUnderlyings[i]).approve(address(morpho), amount);
            morpho.supply(allUnderlyings[i], amount, address(this), 4);
            morpho.withdraw(allUnderlyings[i], amount, address(this), address(this), 4);
        }
    }

    function _network() internal view virtual override returns (string memory) {
        return "avalanche-mainnet";
    }

    function _rewardsManager() internal view virtual override returns (address) {
        return address(rewardsManager);
    }

    function testShouldClaimRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balanceBefore = user.balanceOf(rewardToken);

        (address[] memory rewardTokens, uint256[] memory claimedAmounts) =
            wrappedNativeTokenSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens.length, 1);
        assertEq(rewardTokens[0], rewardToken);
        assertEq(claimedAmounts.length, 1);

        uint256 balanceAfter = user.balanceOf(rewardToken);

        assertGt(claimedAmounts[0], 0);
        assertApproxEqAbs(
            ERC20(rewardToken).balanceOf(address(wrappedNativeTokenSupplyVault)),
            0,
            1,
            "non zero rewardToken balance on vault"
        );
        assertEq(balanceAfter, balanceBefore + claimedAmounts[0], "unexpected rewardToken balance");
    }

    function testShouldClaimTwiceRewardsWhenDepositedForSameAmountAndTwiceDuration(uint256 amount, uint256 timePassed)
        public
    {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        promoter1.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) =
            wrappedNativeTokenSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));

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
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        uint256 shares1 = user.depositVault(wrappedNativeTokenSupplyVault, amount);
        uint256 shares2 = promoter1.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);
        promoter1.redeemVault(wrappedNativeTokenSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);
        promoter1.redeemVault(wrappedNativeTokenSupplyVault, shares2 / 2);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) =
            wrappedNativeTokenSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        assertApproxEqAbs(
            expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0], 5, "unexpected total rewards amount"
        );
        assertGe(expectedTotalRewardsAmount, claimedAmounts1[0] + claimedAmounts2[0]);
        assertApproxEqAbs(claimedAmounts1[0], claimedAmounts2[0], 1, "unexpected rewards amount"); // not exact because of rewardTokenounded interests
    }

    function testShouldClaimSameRewardsWhenDepositedForSameAmountAndDuration1(uint256 amount, uint256 timePassed)
        public
    {
        // This test depends on reward distribution being somewhat invariant, which is violated if the amount is too large.
        // So we use a different bound than usual.
        amount = bound(amount, testMarkets[wNative].minAmount, 10000 ether);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        uint256 shares1 = user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        uint256 shares2 = promoter1.depositVault(wrappedNativeTokenSupplyVault, amount);
        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);
        promoter1.redeemVault(wrappedNativeTokenSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) =
            wrappedNativeTokenSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));

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
        // This test depends on reward distribution being somewhat invariant, which is violated if the amount is too large.
        // So we use a different bound than usual.
        amount = bound(amount, testMarkets[wNative].minAmount, 10000 ether);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        uint256 shares1 = user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        uint256 shares2 = promoter1.depositVault(wrappedNativeTokenSupplyVault, amount);
        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        uint256 shares3 = promoter2.depositVault(wrappedNativeTokenSupplyVault, amount);
        user.redeemVault(wrappedNativeTokenSupplyVault, shares1 / 2);
        promoter1.redeemVault(wrappedNativeTokenSupplyVault, shares2 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        promoter1.redeemVault(wrappedNativeTokenSupplyVault, shares2 / 2);
        promoter2.redeemVault(wrappedNativeTokenSupplyVault, shares3 / 2);

        vm.warp(block.timestamp + timePassed);

        expectedTotalRewardsAmount +=
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        promoter2.redeemVault(wrappedNativeTokenSupplyVault, shares3 / 2);

        (address[] memory rewardTokens1, uint256[] memory claimedAmounts1) =
            wrappedNativeTokenSupplyVault.claimRewards(address(user));

        assertEq(rewardTokens1.length, 1);
        assertEq(rewardTokens1[0], rewardToken);
        assertEq(claimedAmounts1.length, 1);

        (address[] memory rewardTokens2, uint256[] memory claimedAmounts2) =
            wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));

        assertEq(rewardTokens2.length, 1);
        assertEq(rewardTokens2[0], rewardToken);
        assertEq(claimedAmounts2.length, 1);

        (address[] memory rewardTokens3, uint256[] memory claimedAmounts3) =
            wrappedNativeTokenSupplyVault.claimRewards(address(promoter2));

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
            ERC20(rewardToken).balanceOf(address(wrappedNativeTokenSupplyVault)),
            0,
            1,
            "non zero rewardToken balance on vault"
        );
        assertApproxEqAbs(claimedAmounts1[0], claimedAmounts2[0], 1, "unexpected rewards amount 1-2"); // not exact because of rewardTokenounded interests
        assertApproxEqAbs(claimedAmounts2[0], claimedAmounts3[0], 1, "unexpected rewards amount 2-3"); // not exact because of rewardTokenounded interests
    }

    function testRewardsShouldAccrueWhenDepositingOnBehalf(uint256 amount, uint256 timePassed) public {
        // This test depends on reward distribution being somewhat invariant, which is violated if the amount is too large.
        // So we use a different bound than usual.
        amount = bound(amount, testMarkets[wNative].minAmount, 10000 ether);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        promoter1.depositVault(wrappedNativeTokenSupplyVault, amount, address(user));
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        // Should update the unclaimed amount
        promoter1.depositVault(wrappedNativeTokenSupplyVault, amount, address(user));
        uint256 userReward1_1 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        vm.warp(block.timestamp + timePassed);
        uint256 userReward1_2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        uint256 userReward2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);
        assertEq(userReward2, 0);
        assertGt(userReward1_1, 0);
        assertGt(userReward1_2, 0);
        assertApproxEqAbs(userReward1_1, expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(userReward1_1 * 3, userReward1_2, userReward1_2 / 100);
    }

    function testRewardsShouldAccrueWhenMintingOnBehalf(uint256 amount, uint256 timePassed) public {
        // This test depends on reward distribution being somewhat invariant, which is violated if the amount is too large.
        // So we use a different bound than usual.
        amount = bound(amount, testMarkets[wNative].minAmount, 10000 ether);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        promoter1.mintVault(
            wrappedNativeTokenSupplyVault, wrappedNativeTokenSupplyVault.previewMint(amount), address(user)
        );
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        // Should update the unclaimed amount
        promoter1.mintVault(
            wrappedNativeTokenSupplyVault, wrappedNativeTokenSupplyVault.previewMint(amount), address(user)
        );

        uint256 userReward1_1 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        vm.warp(block.timestamp + timePassed);
        uint256 userReward1_2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);

        uint256 userReward2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);
        assertEq(userReward2, 0);
        assertGt(userReward1_1, 0);
        assertApproxEqAbs(userReward1_1, expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(userReward1_1 * 3, userReward1_2, userReward1_2 / 100);
    }

    function testRewardsShouldAccrueWhenRedeemingToReceiver(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        user.depositVault(wrappedNativeTokenSupplyVault, amount);
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        // Should update the unclaimed amount
        user.redeemVault(
            wrappedNativeTokenSupplyVault,
            wrappedNativeTokenSupplyVault.balanceOf(address(user)),
            address(promoter1),
            address(user)
        );
        (, uint128 userReward1_1) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(user));

        vm.warp(block.timestamp + timePassed);

        uint256 userReward1_2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 userReward2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        (uint128 index2,) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, 0);
        assertEq(userReward2, 0);
        assertGt(uint256(userReward1_1), 0);
        assertApproxEqAbs(uint256(userReward1_1), expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(uint256(userReward1_1), userReward1_2, 1);
    }

    function testRewardsShouldAccrueWhenWithdrawingToReceiver(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);
        address[] memory poolTokens = new address[](1);
        poolTokens[0] = testMarkets[wNative].aToken;

        user.depositVault(wrappedNativeTokenSupplyVault, amount);
        vm.warp(block.timestamp + timePassed);

        uint256 expectedTotalRewardsAmount =
            rewardsManager.getUserRewards(poolTokens, address(wrappedNativeTokenSupplyVault), rewardToken);

        // Should update the unclaimed amount
        user.withdrawVault(
            wrappedNativeTokenSupplyVault,
            wrappedNativeTokenSupplyVault.maxWithdraw(address(user)),
            address(promoter1),
            address(user)
        );

        (, uint128 userReward1_1) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(user));

        vm.warp(block.timestamp + timePassed);

        uint256 userReward1_2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 userReward2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        (uint128 index2,) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, 0);
        assertEq(userReward2, 0);
        assertGt(uint256(userReward1_1), 0);
        assertApproxEqAbs(uint256(userReward1_1), expectedTotalRewardsAmount, 1);
        assertApproxEqAbs(uint256(userReward1_1), userReward1_2, 1);
    }

    function testTransferAccrueRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = wrappedNativeTokenSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        wrappedNativeTokenSupplyVault.transfer(address(promoter1), balance);

        uint256 rewardAmount = ERC20(rewardToken).balanceOf(address(wrappedNativeTokenSupplyVault));
        assertGt(rewardAmount, 0, "rewardAmount = 0");

        uint256 expectedIndex = rewardAmount.rayDiv(wrappedNativeTokenSupplyVault.totalSupply());
        uint256 rewardsIndex = wrappedNativeTokenSupplyVault.rewardsIndex(rewardToken);
        assertApproxEqAbs(expectedIndex, rewardsIndex, 1, "rewardsIndex");

        (uint256 index1, uint256 unclaimed1) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(user));
        assertEq(index1, rewardsIndex, "index1");
        assertApproxEqAbs(unclaimed1, rewardAmount, 1, "unclaimed1");

        (uint256 index2, uint256 unclaimed2) =
            wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, rewardsIndex, "index2");
        assertEq(unclaimed2, 0, "unclaimed2");

        (, uint256[] memory rewardsAmount1) = wrappedNativeTokenSupplyVault.claimRewards(address(user));
        (, uint256[] memory rewardsAmount2) = wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));
        assertGt(rewardsAmount1[0], 0, "rewardsAmount1");
        assertEq(rewardsAmount2[0], 0, "rewardsAmount2");
    }

    function testTransferFromAccrueRewards(uint256 amount, uint256 timePassed) public {
        amount = _boundSupply(testMarkets[wNative], amount);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = wrappedNativeTokenSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        wrappedNativeTokenSupplyVault.approve(address(promoter2), balance);

        vm.prank(address(promoter2));
        wrappedNativeTokenSupplyVault.transferFrom(address(user), address(promoter1), balance);

        uint256 rewardAmount = ERC20(rewardToken).balanceOf(address(wrappedNativeTokenSupplyVault));
        assertGt(rewardAmount, 0, "rewardAmount = 0");

        uint256 expectedIndex = rewardAmount.rayDiv(wrappedNativeTokenSupplyVault.totalSupply());
        uint256 rewardsIndex = wrappedNativeTokenSupplyVault.rewardsIndex(rewardToken);
        assertApproxEqAbs(rewardsIndex, expectedIndex, 1, "rewardIndex != expectedIndex");

        (uint256 index1, uint256 unclaimed1) = wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(user));
        assertEq(index1, rewardsIndex, "index1 != rewardsIndex");
        assertApproxEqAbs(unclaimed1, rewardAmount, 1, "unclaimed1 != rewardAmount");

        (uint256 index2, uint256 unclaimed2) =
            wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(promoter1));
        assertEq(index2, rewardsIndex, "index2 != rewardsIndex");
        assertEq(unclaimed2, 0, "unclaimed2 != 0");

        (uint256 index3, uint256 unclaimed3) =
            wrappedNativeTokenSupplyVault.userRewards(rewardToken, address(promoter2));
        assertEq(index3, 0, "index3 != 0");
        assertEq(unclaimed3, 0, "unclaimed3 != 0");

        (, uint256[] memory rewardsAmount1) = wrappedNativeTokenSupplyVault.claimRewards(address(user));
        (, uint256[] memory rewardsAmount2) = wrappedNativeTokenSupplyVault.claimRewards(address(promoter1));
        (, uint256[] memory rewardsAmount3) = wrappedNativeTokenSupplyVault.claimRewards(address(promoter2));
        assertGt(rewardsAmount1[0], 0, "rewardsAmount1");
        assertEq(rewardsAmount2[0], 0, "rewardsAmount2");
        assertEq(rewardsAmount3[0], 0, "rewardsAmount3");
    }

    function testTransferAndClaimRewards(uint256 amount, uint256 timePassed) public {
        // This test depends on reward distribution being somewhat invariant, which is violated if the amount is too large.
        // So we use a different bound than usual.
        amount = bound(amount, testMarkets[wNative].minAmount, 10000 ether);
        timePassed = bound(timePassed, 1, 10 days);

        user.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        promoter1.depositVault(wrappedNativeTokenSupplyVault, amount);

        vm.warp(block.timestamp + timePassed);

        uint256 balance = wrappedNativeTokenSupplyVault.balanceOf(address(user));
        vm.prank(address(user));
        wrappedNativeTokenSupplyVault.transfer(address(promoter1), balance);

        vm.warp(block.timestamp + timePassed);

        uint256 rewardsAmount1 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(user), rewardToken);
        uint256 rewardsAmount2 = wrappedNativeTokenSupplyVault.getUnclaimedRewards(address(promoter1), rewardToken);

        assertGt(rewardsAmount1, 0, "rewardsAmount1");
        assertApproxEqAbs(rewardsAmount1, (2 * rewardsAmount2) / 3, rewardsAmount1 / 100, "rewardsAmounts");
        // Why rewardsAmount1 is 2/3 of rewardsAmount2 can be explained as follows:
        // user first gets X rewards corresponding to amount over one period of time
        // user and promoter1 get X rewards each (under the approximation that doubling the amount doubles the rewards)
        // promoter1 then gets 2 * X rewards
        // In the end, user got 2 * X rewards while promoter1 got 3 * X
    }
}
