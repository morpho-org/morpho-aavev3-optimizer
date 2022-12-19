// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

library Constants {
    uint8 internal constant NO_REFERRAL_CODE = 0;
    uint8 internal constant VARIABLE_INTEREST_MODE = 2;
    uint256 internal constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000; // 50% in basis points.
    uint256 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.
    uint256 internal constant MAX_NB_OF_MARKETS = 128;
    uint256 internal constant MAX_LIQUIDATION_CLOSE_FACTOR = 10_000; // 100% in basis points.
    uint256 internal constant MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 0.95e18; // Health factor below which the positions can be liquidated, whether or not the price oracle sentinel allows the liquidation.
    bytes32 internal constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;
    bytes32 internal constant ONE = 0x0000000000000000000000000000000000000000000000000000000000000001;
}
