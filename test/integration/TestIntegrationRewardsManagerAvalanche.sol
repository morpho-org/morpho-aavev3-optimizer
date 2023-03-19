// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRewardsManagerAvalanche is IntegrationTest {
    using TestConfigLib for TestConfig;

    function setUp() public virtual override {
        super.setUp();
        rewardsController = IRewardsController(config.getRewardsController());
        rewardsManager = IRewardsManager(new RewardsManager(address(rewardsController), address(morpho)));
        morpho.setRewardsManager(address(rewardsManager));
    }

    /// @dev We can only use avalanche mainnet because mainnet doesn't have a rewards controller yet
    function _network() internal view virtual override returns (string memory) {
        return "avalanche-mainnet";
    }

    function testWorking() public {
        assertTrue(true);
    }
}
