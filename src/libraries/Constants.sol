// SPDX-License-Identifier: AGPL-3.0-only
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

    bool internal constant HEAD = true;

    string internal constant EIP712_MSG_PREFIX = "\x19\x01";
    string internal constant EIP712_NAME = "Morpho-AaveV3";
    string internal constant EIP712_VERSION = "0";
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"); // The EIP-712 typehash for the contract's domain.
    bytes32 internal constant EIP712_AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address owner,address manager,bool isAllowed,uint256 nonce,uint256 deadline)"); // The EIP-712 typehash for approveManagerBySig Authorization.

    uint256 internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0; // The highest valid value for s in an ECDSA signature pair (0 < s < secp256k1n ÷ 2 + 1)
}
