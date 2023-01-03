// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IRewardsManager {
    function claimRewards(address[] calldata assets, address user) external;

    function updateUserAssetAndAccruedRewards(address user, address asset, uint256 userBalance) external;
}
