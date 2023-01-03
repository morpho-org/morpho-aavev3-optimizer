// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRewardsManager {
    function claimRewards(address[] calldata assets, address user) external;

    function updateUserRewards(address user, address asset, uint256 userBalance) external;
}
