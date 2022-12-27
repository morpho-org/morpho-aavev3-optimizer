// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

library Constants {
    uint8 internal constant NO_REFERRAL_CODE = 0;
    uint8 internal constant VARIABLE_INTEREST_MODE = 2;

    uint256 internal constant MAX_CLOSE_FACTOR = PercentageMath.PERCENTAGE_FACTOR;
    uint256 internal constant DEFAULT_CLOSE_FACTOR = PercentageMath.HALF_PERCENTAGE_FACTOR;
    uint256 internal constant DEFAULT_LIQUIDATION_THRESHOLD = WadRayMath.WAD; // Health factor below which the positions can be liquidated.
    uint256 internal constant MIN_LIQUIDATION_THRESHOLD = 0.95e18; // Health factor below which the positions can be liquidated, whether or not the price oracle sentinel allows the liquidation.

    uint256 internal constant MAX_NB_MARKETS = 128;
    bytes32 internal constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;
    bytes32 internal constant ONE = 0x0000000000000000000000000000000000000000000000000000000000000001;
}
