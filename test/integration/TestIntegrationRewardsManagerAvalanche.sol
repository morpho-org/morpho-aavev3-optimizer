// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRewardsManagerAvalanche is IntegrationTest {
    using TestConfigLib for TestConfig;

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
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));
        for (uint256 i; i < rewardTokens.length; i++) {
            console2.log(rewardTokens[i]);
            console2.log(amounts[i]);
        }
    }

    function testClaimRewardsWhenSupplyingCollateral() public {
        user.approve(dai, 100 ether);
        user.supplyCollateral(dai, 100 ether);
        _forward(10);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));
        for (uint256 i; i < rewardTokens.length; i++) {
            console2.log(rewardTokens[i]);
            console2.log(amounts[i]);
        }
    }
}
