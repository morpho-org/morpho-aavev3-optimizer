// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRewardsManager {
    function claimRewards(address[] calldata assets, address user)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function updateUserRewards(address user, address asset, uint256 userBalance) external;
    function getRewardsController() external view returns (address);
    function getMorpho() external view returns (address);
    function getPool() external view returns (address);
}
