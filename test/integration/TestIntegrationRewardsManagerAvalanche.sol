// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRewardsManagerAvalanche is IntegrationTest {
    using TestConfigLib for TestConfig;

    // From the rewards manager
    event Accrued(
        address indexed asset, address indexed reward, address indexed user, uint256 assetIndex, uint256 rewardsAccrued
    );

    address[] internal assets;

    function setUp() public virtual override {
        super.setUp();
        rewardsController = IRewardsController(config.getRewardsController());
        rewardsManager = IRewardsManager(new RewardsManager(address(rewardsController), address(morpho)));
        morpho.setRewardsManager(address(rewardsManager));
        assets = [testMarkets[dai].aToken, testMarkets[dai].variableDebtToken];
    }

    /// @dev We can only use avalanche mainnet because mainnet doesn't have a rewards controller yet
    function _network() internal view virtual override returns (string memory) {
        return "avalanche-mainnet";
    }

    function testClaimRewardsRevertIfPaused() public {
        morpho.setIsClaimRewardsPaused(true);

        vm.expectRevert(Errors.ClaimRewardsPaused.selector);
        morpho.claimRewards(assets, address(this));
    }

    function testClaimRewardsRevertIfRewardsManagerZero() public {
        morpho.setRewardsManager(address(0));

        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.claimRewards(assets, address(this));
    }

    function testClaimRewardsWhenSupplyingPool() public {
        user.approve(dai, 100 ether);
        user.supply(dai, 100 ether);
        _forward(10);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);

        // TODO: See if we can predict the index for testing the event data.
        vm.expectEmit(true, true, true, false);
        emit Accrued(testMarkets[dai].aToken, wNative, address(user), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1);
        assertEq(amounts.length, 1);
        assertEq(rewardTokens[0], wNative);
        assertEq(amounts[0], accruedRewards, "amount");
        assertGt(amounts[0], 0, "amount = 0");
    }

    function testClaimRewardsWhenSupplyingCollateral() public {
        user.approve(dai, 100 ether);
        user.supplyCollateral(dai, 100 ether);
        _forward(10);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);

        // TODO: See if we can predict the index for testing the event data.
        vm.expectEmit(true, true, true, false);
        emit Accrued(testMarkets[dai].aToken, wNative, address(user), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1);
        assertEq(amounts.length, 1);
        assertEq(rewardTokens[0], wNative);
        assertEq(amounts[0], accruedRewards, "amount");
        assertGt(amounts[0], 0, "amount = 0");
    }

    function testClaimRewardsWhenBorrowingPool() public {
        user.approve(wbtc, 1e8); // wbtc has no rewards and so 1 BTC will make for a clean collateral for a test
        user.supplyCollateral(wbtc, 1e8);
        user.borrow(dai, 100 ether);
        _forward(10);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);

        // TODO: See if we can predict the index for testing the event data.
        vm.expectEmit(true, true, true, false);
        emit Accrued(testMarkets[dai].variableDebtToken, wNative, address(user), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1);
        assertEq(amounts.length, 1);
        assertEq(rewardTokens[0], wNative);
        assertEq(amounts[0], accruedRewards, "amount");
        assertGt(amounts[0], 0, "amount = 0");
    }
}
