// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {MorphoInternal, MorphoStorage} from "./MorphoInternal.sol";
import {IGovernanceManager} from "./interfaces/IGovernanceManager.sol";

import {IRewardsController} from "@aave-v3-periphery/rewards/interfaces/IRewardsController.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";

contract GovernanceManager is IGovernanceManager, MorphoInternal {
    using SafeTransferLib for ERC20;

    constructor(address addressesProvider, uint8 eModeCategoryId) MorphoStorage(addressesProvider, eModeCategoryId) {}

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external {
        _createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function increaseP2PDeltas(address underlying, uint256 amount) external {
        _increaseP2PDeltas(underlying, amount);
    }

    function claimRewards(address[] calldata assets, address onBehalf)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        if (_isClaimRewardsPaused) revert Errors.ClaimRewardsPaused();

        (rewardTokens, claimedAmounts) = _rewardsManager.claimRewards(assets, onBehalf);
        IRewardsController(_rewardsManager.getRewardsController()).claimAllRewardsToSelf(assets);

        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 claimedAmount = claimedAmounts[i];

            if (claimedAmount > 0) {
                ERC20(rewardTokens[i]).safeTransfer(onBehalf, claimedAmount);
                emit Events.RewardsClaimed(onBehalf, rewardTokens[i], claimedAmount);
            }
        }
    }
}
