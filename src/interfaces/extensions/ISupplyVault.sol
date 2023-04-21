// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IRewardsManager} from "src/interfaces/IRewardsManager.sol";
import {ISupplyVaultBase} from "src/interfaces/extensions/ISupplyVaultBase.sol";

interface ISupplyVault is ISupplyVaultBase {
    /* EVENTS */

    /// @notice Emitted when rewards of an asset are accrued on behalf of a user.
    /// @param rewardToken The address of the reward token.
    /// @param user The address of the user that rewards are accrued on behalf of.
    /// @param index The index of the asset distribution on behalf of the user.
    /// @param unclaimed The new unclaimed amount of the user.
    event Accrued(address indexed rewardToken, address indexed user, uint256 index, uint256 unclaimed);

    /// @notice Emitted when rewards of an asset are claimed on behalf of a user.
    /// @param rewardToken The address of the reward token.
    /// @param user The address of the user that rewards are claimed on behalf of.
    /// @param claimed The amount of rewards claimed.
    event Claimed(address indexed rewardToken, address indexed user, uint256 claimed);

    /* STRUCTS */

    struct UserRewardsData {
        uint128 index; // User rewards index for a given reward token (in ray).
        uint128 unclaimed; // Unclaimed amount for a given reward token (in reward tokens).
    }

    /* FUNCTIONS */

    function REWARDS_MANAGER() external view returns (IRewardsManager);

    function rewardsIndex(address rewardToken) external view returns (uint128);

    function userRewards(address rewardToken, address user) external view returns (uint128, uint128);

    function getAllUnclaimedRewards(address user)
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts);

    function getUnclaimedRewards(address user, address rewardToken) external view returns (uint256);

    function claimRewards(address user)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts);
}
