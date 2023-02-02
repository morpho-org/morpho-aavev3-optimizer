// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

/// @title Constants
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing constants used in Morpho.
library Constants {
    uint8 internal constant NO_REFERRAL_CODE = 0;
    uint8 internal constant VARIABLE_INTEREST_MODE = 2;

    uint256 internal constant MAX_CLOSE_FACTOR = PercentageMath.PERCENTAGE_FACTOR;
    uint256 internal constant DEFAULT_CLOSE_FACTOR = PercentageMath.HALF_PERCENTAGE_FACTOR;
    uint256 internal constant DEFAULT_LIQUIDATION_THRESHOLD = WadRayMath.WAD; // Health factor below which the positions can be liquidated.
    uint256 internal constant MIN_LIQUIDATION_THRESHOLD = 0.95e18; // Health factor below which the positions can be liquidated, whether or not the price oracle sentinel allows the liquidation.

    string internal constant EIP712_NAME = "Morpho-AaveV3";
    string internal constant EIP712_VERSION = "0";
    bytes32 internal constant APPROVE_MANAGER_TYPEHASH =
        keccak256("ApproveManager(address delegator,address manager,bool isAllowed,uint256 nonce,uint256 deadline)"); // The EIP-712 typehash for approveManagerBySig Authorization.
}
