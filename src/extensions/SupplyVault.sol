// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IRewardsManager} from "src/interfaces/IRewardsManager.sol";
import {ISupplyVault} from "src/interfaces/extensions/ISupplyVault.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {SafeCastLib} from "@solmate/utils/SafeCastLib.sol";

import {SupplyVaultBase} from "./SupplyVaultBase.sol";

/// @title SupplyVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable Tokenized Vault implementation for Morpho-Aave V3, which tracks rewards from Aave's pool accrued by its users.
contract SupplyVault is ISupplyVault, SupplyVaultBase {
    using WadRayMath for uint256;
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;

    /// CONSTANTS AND IMMUTABLES ///

    IRewardsManager internal immutable _rewardsManager; // Morpho's rewards manager.

    /// STORAGE ///

    mapping(address => uint128) internal _rewardsIndex; // The current reward index for the given reward token.
    mapping(address => mapping(address => UserRewardsData)) internal _userRewards; // User rewards data. rewardToken -> user -> userRewards.

    /// CONSTRUCTOR ///

    /// @dev Initializes network-wide immutables.
    /// @param newMorpho The address of the main Morpho contract.
    /// @param newMorphoToken The address of the Morpho Token.
    /// @param newRecipient The recipient of the rewards that will redistribute them to vault's users.
    constructor(address newMorpho, address newMorphoToken, address newRecipient)
        SupplyVaultBase(newMorpho, newMorphoToken, newRecipient)
    {
        _rewardsManager = IRewardsManager(_morpho.rewardsManager());
    }

    /// INITIALIZER ///

    /// @dev Initializes the vault.
    /// @param newUnderlying The address of the pool token corresponding to the market to supply through this vault.
    /// @param name The name of the ERC20 token associated to this tokenized vault.
    /// @param symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    /// @param newMaxIterations The max iterations to use when this vault interacts with Morpho.
    function initialize(
        address newUnderlying,
        string calldata name,
        string calldata symbol,
        uint256 initialDeposit,
        uint8 newMaxIterations
    ) external initializer {
        __SupplyVaultBase_init(newUnderlying, name, symbol, initialDeposit, newMaxIterations);
    }

    /// EXTERNAL ///

    /// @notice Claims rewards on behalf of `_user`.
    /// @param user The address of the user to claim rewards for.
    /// @return rewardTokens The list of reward tokens.
    /// @return claimedAmounts The list of claimed amounts for each reward tokens.
    function claimRewards(address user)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        (rewardTokens, claimedAmounts) = _accrueUnclaimedRewards(user);

        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 claimedAmount = claimedAmounts[i];
            if (claimedAmount == 0) continue;

            address rewardToken = rewardTokens[i];
            _userRewards[rewardToken][user].unclaimed = 0;

            ERC20(rewardToken).safeTransfer(user, claimedAmount);

            emit Claimed(rewardToken, user, claimedAmount);
        }
    }

    /// @notice Returns a given user's unclaimed rewards for all reward tokens.
    /// @param user The address of the user.
    /// @return rewardTokens The list of reward tokens.
    /// @return unclaimedAmounts The list of unclaimed amounts for each reward token.
    function getAllUnclaimedRewards(address user)
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts)
    {
        address[] memory underlyings = new address[](1);
        underlyings[0] = _underlying;

        uint256[] memory claimableAmounts;
        (rewardTokens, claimableAmounts) = _rewardsManager.getAllUserRewards(underlyings, address(this));

        unclaimedAmounts = new uint256[](claimableAmounts.length);
        uint256 supply = totalSupply();

        for (uint256 i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            unclaimedAmounts[i] = _getUpdatedUnclaimedReward(user, rewardToken, claimableAmounts[i], supply);
        }
    }

    /// @notice Returns user's rewards for the specificied reward token.
    /// @param user The address of the user.
    /// @param rewardToken The address of the reward token
    /// @return The user's rewards in reward token.
    function getUnclaimedRewards(address user, address rewardToken) external view returns (uint256) {
        address[] memory underlyings = new address[](1);
        underlyings[0] = _underlying;

        uint256 claimableRewards = _rewardsManager.getUserRewards(underlyings, address(this), rewardToken);

        return _getUpdatedUnclaimedReward(user, rewardToken, claimableRewards, totalSupply());
    }

    function rewardsIndex(address rewardToken) external view returns (uint128) {
        return _rewardsIndex[rewardToken];
    }

    function rewardsManager() external view returns (IRewardsManager) {
        return _rewardsManager;
    }

    function userRewards(address rewardToken, address user) external view returns (uint128 index, uint128 unclaimed) {
        UserRewardsData memory userRewardsData = _userRewards[rewardToken][user];
        return (userRewardsData.index, userRewardsData.unclaimed);
    }

    /// INTERNAL ///

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        (address[] memory rewardTokens, uint256[] memory rewardsIndexes) = _claimVaultRewards();
        _accrueUnclaimedRewardsFromRewardIndexes(from, rewardTokens, rewardsIndexes);
        _accrueUnclaimedRewardsFromRewardIndexes(to, rewardTokens, rewardsIndexes);

        super._beforeTokenTransfer(from, to, amount);
    }

    function _claimVaultRewards() internal returns (address[] memory rewardTokens, uint256[] memory rewardsIndexes) {
        address[] memory underlyings = new address[](1);
        underlyings[0] = _underlying;

        uint256[] memory claimedAmounts;
        (rewardTokens, claimedAmounts) = _morpho.claimRewards(underlyings, address(this));

        rewardsIndexes = new uint256[](rewardTokens.length);

        uint256 supply = totalSupply();
        for (uint256 i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            uint256 newRewardIndex = _rewardsIndex[rewardToken] + _getUnaccruedRewardIndex(claimedAmounts[i], supply);

            rewardsIndexes[i] = newRewardIndex;
            _rewardsIndex[rewardToken] = newRewardIndex.safeCastTo128();
        }
    }

    function _accrueUnclaimedRewards(address user)
        internal
        returns (address[] memory rewardTokens, uint256[] memory unclaimedAmounts)
    {
        uint256[] memory rewardsIndexes;
        (rewardTokens, rewardsIndexes) = _claimVaultRewards();

        unclaimedAmounts = _accrueUnclaimedRewardsFromRewardIndexes(user, rewardTokens, rewardsIndexes);
    }

    function _accrueUnclaimedRewardsFromRewardIndexes(
        address user,
        address[] memory rewardTokens,
        uint256[] memory rewardIndexes
    ) internal returns (uint256[] memory unclaimedAmounts) {
        if (user == address(0)) return unclaimedAmounts;

        unclaimedAmounts = new uint256[](rewardTokens.length);

        for (uint256 i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            uint256 rewardIndex = rewardIndexes[i];

            UserRewardsData storage userRewardsData = _userRewards[rewardToken][user];

            // Safe because we always have `rewardsIndex` >= `userRewardsData.index`.
            uint256 rewardsIndexDiff;
            unchecked {
                rewardsIndexDiff = rewardIndex - userRewardsData.index;
            }

            uint256 unclaimedAmount = userRewardsData.unclaimed;
            if (rewardsIndexDiff > 0) {
                unclaimedAmount += _getUnaccruedRewardsFromRewardsIndexAccrual(user, rewardsIndexDiff);
                userRewardsData.unclaimed = unclaimedAmount.safeCastTo128();
                userRewardsData.index = rewardIndex.safeCastTo128();

                emit Accrued(rewardToken, user, rewardIndex, unclaimedAmount);
            }

            unclaimedAmounts[i] = unclaimedAmount;
        }
    }

    function _getUpdatedUnclaimedReward(address user, address rewardToken, uint256 claimableReward, uint256 totalSupply)
        internal
        view
        returns (uint256 unclaimed)
    {
        UserRewardsData memory userRewardsData = _userRewards[rewardToken][user];
        unclaimed = userRewardsData.unclaimed
            + _getUnaccruedRewardsFromRewardsIndexAccrual(
                user,
                _getUnaccruedRewardIndex(claimableReward, totalSupply) // The unaccrued reward index
                    + _rewardsIndex[rewardToken] - userRewardsData.index // The difference between the current reward index and the user's index
            );
    }

    function _getUnaccruedRewardsFromRewardsIndexAccrual(address user, uint256 indexAccrual)
        internal
        view
        returns (uint256 unaccruedReward)
    {
        unaccruedReward = balanceOf(user).rayMulDown(indexAccrual); // Equivalent to rayMul rounded down
    }

    function _getUnaccruedRewardIndex(uint256 claimableReward, uint256 totalSupply)
        internal
        pure
        returns (uint256 unaccruedRewardIndex)
    {
        if (totalSupply > 0) unaccruedRewardIndex = claimableReward.rayDivDown(totalSupply); // Equivalent to rayDiv rounded down
    }
}
