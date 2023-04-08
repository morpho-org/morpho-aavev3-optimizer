// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRewardsManager {
    function MORPHO() external view returns (address);
    function REWARDS_CONTROLLER() external view returns (address);

    function getRewardData(address asset, address reward)
        external
        view
        returns (uint256 startingIndex, uint256 index, uint256 lastUpdateTimestamp);
    function getUserData(address asset, address reward, address user)
        external
        view
        returns (uint256 index, uint256 accrued);

    function getAllUserRewards(address[] calldata assets, address user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);
    function getUserRewards(address[] calldata assets, address user, address reward) external view returns (uint256);
    function getUserAccruedRewards(address[] calldata assets, address user, address reward)
        external
        view
        returns (uint256 totalAccrued);
    function getUserAssetIndex(address user, address asset, address reward) external view returns (uint256);
    function getAssetIndex(address asset, address reward) external view returns (uint256 assetIndex);

    function claimRewards(address[] calldata assets, address user)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function updateUserRewards(address user, address asset, uint256 userBalance) external;
}
