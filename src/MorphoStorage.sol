// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";

import {Types} from "./libraries/Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

abstract contract MorphoStorage is Initializable, Ownable2StepUpgradeable {
    /// IMMUTABLES ///

    IPool internal immutable _POOL;
    IPoolAddressesProvider internal immutable _ADDRESSES_PROVIDER;
    bytes32 internal immutable _DOMAIN_SEPARATOR;
    uint8 internal immutable _E_MODE_CATEGORY_ID;

    /// STORAGE ///

    address[] internal _marketsCreated; // Keeps track of the created markets.
    mapping(address => Types.Market) internal _market;
    mapping(address => Types.MarketBalances) internal _marketBalances;
    mapping(address => EnumerableSet.AddressSet) internal _userCollaterals; // The collateral markets entered by a user.
    mapping(address => EnumerableSet.AddressSet) internal _userBorrows; // The borrow markets entered by a user.
    mapping(address => mapping(address => bool)) internal _isManaging; // Whether a user is allowed to borrow or withdraw on behalf of another user. owner => manager => bool
    mapping(address => uint256) internal _userNonce; // The nonce of a user. Used to prevent replay attacks.

    Types.MaxLoops internal _defaultMaxLoops;

    address internal _positionsManager;
    IRewardsManager internal _rewardsManager;

    address internal _treasuryVault;
    bool internal _isClaimRewardsPaused; // Whether claiming rewards is paused or not.

    /// @dev The contract is automatically marked as initialized when deployed to prevent highjacking the implementation contract.
    constructor(address addressesProvider, uint8 eModeCategoryId) {
        _disableInitializers();

        _ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
        _POOL = IPool(_ADDRESSES_PROVIDER.getPool());

        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                Constants.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(Constants.EIP712_NAME)),
                keccak256(bytes(Constants.EIP712_VERSION)),
                block.chainid,
                address(this)
            )
        );

        _E_MODE_CATEGORY_ID = eModeCategoryId;
    }
}
