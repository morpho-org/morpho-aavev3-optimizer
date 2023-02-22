// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationClaimRewards is IntegrationTest {
    address[] internal assets = [testMarkets[dai].aToken, testMarkets[dai].variableDebtToken];

    function setUp() public override {
        super.setUp();

        morpho.setRewardsManager(address(rewardsManagerMock));
    }

    function testClaimRewardsRevertIfPaused() public {
        morpho.setIsClaimRewardsPaused(true);

        vm.expectRevert(Errors.ClaimRewardsPaused.selector);
        morpho.claimRewards(assets, address(this));
    }

    function testClaimRewardsIfNotPaused() public {
        vm.expectRevert(RewardsManagerMock.ForcedRevert.selector);
        morpho.claimRewards(assets, address(this));
    }
}
