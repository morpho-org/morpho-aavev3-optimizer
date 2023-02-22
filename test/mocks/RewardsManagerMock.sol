// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

contract RewardsManagerMock {
    error ForcedRevert();

    function claimRewards(address[] calldata assets, address)
        external
        pure
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        rewardsList = new address[](assets.length);
        claimedAmounts = new uint256[](assets.length);
    }

    function REWARDS_CONTROLLER() external pure returns (address) {
        revert ForcedRevert();
    }
}
