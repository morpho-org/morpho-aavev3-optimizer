// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {
    IRewardsController,
    IEACAggregatorProxy,
    ITransferStrategyBase,
    RewardsDataTypes
} from "@aave-v3-periphery/rewards/interfaces/IRewardsController.sol";

contract RewardsControllerMock is IRewardsController {
    function setDistributionEnd(address asset, address reward, uint32 newDistributionEnd) external {}

    function setEmissionPerSecond(address asset, address[] calldata rewards, uint88[] calldata newEmissionsPerSecond)
        external
    {}

    function getDistributionEnd(address asset, address reward) external view returns (uint256) {}

    function getUserAssetIndex(address user, address asset, address reward) external view returns (uint256) {}

    function getRewardsData(address asset, address reward) external view returns (uint256, uint256, uint256, uint256) {}

    function getAssetIndex(address asset, address reward) external view returns (uint256, uint256) {}

    function getRewardsByAsset(address asset) external view returns (address[] memory) {}

    function getRewardsList() external view returns (address[] memory) {}

    function getUserAccruedRewards(address user, address reward) external view returns (uint256) {}

    function getUserRewards(address[] calldata assets, address user, address reward) external view returns (uint256) {}

    function getAllUserRewards(address[] calldata assets, address user)
        external
        view
        returns (address[] memory, uint256[] memory)
    {}

    function getAssetDecimals(address asset) external view returns (uint8) {}

    function EMISSION_MANAGER() external view returns (address) {}

    function getEmissionManager() external view returns (address) {}

    function setEmissionManager(address emissionManager) external {}

    function setClaimer(address user, address claimer) external {}

    function setTransferStrategy(address reward, ITransferStrategyBase transferStrategy) external {}

    function setRewardOracle(address reward, IEACAggregatorProxy rewardOracle) external {}

    function getRewardOracle(address reward) external view returns (address) {}

    function getClaimer(address user) external view returns (address) {}

    function getTransferStrategy(address reward) external view returns (address) {}

    function configureAssets(RewardsDataTypes.RewardsConfigInput[] memory config) external {}

    function handleAction(address user, uint256 userBalance, uint256 totalSupply) external {}

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        returns (uint256)
    {}

    function claimRewardsOnBehalf(address[] calldata assets, uint256 amount, address user, address to, address reward)
        external
        returns (uint256)
    {}

    function claimRewardsToSelf(address[] calldata assets, uint256 amount, address reward) external returns (uint256) {}

    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {}

    function claimAllRewardsOnBehalf(address[] calldata assets, address user, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {}

    function claimAllRewardsToSelf(address[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {}
}
