// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoGetters} from "./interfaces/IMorpho.sol";

import {Types} from "./libraries/Types.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGetters is IMorphoGetters, MorphoInternal {
    using MarketBalanceLib for Types.MarketBalances;

    /// STORAGE ///

    function POOL() external view returns (address) {
        return address(_POOL);
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return address(_ADDRESSES_PROVIDER);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _computeDomainSeparator();
    }

    function market(address underlying) external view returns (Types.Market memory) {
        return _market[underlying];
    }

    function scaledPoolSupplyBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledPoolSupplyBalance(user);
    }

    function scaledP2PSupplyBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledP2PSupplyBalance(user);
    }

    function scaledPoolBorrowBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledPoolBorrowBalance(user);
    }

    function scaledP2PBorrowBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledP2PBorrowBalance(user);
    }

    function scaledCollateralBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledCollateralBalance(user);
    }

    function isManaging(address owner, address manager) external view returns (bool) {
        return _isManaging[owner][manager];
    }

    function userNonce(address user) external view returns (uint256) {
        return _userNonce[user];
    }

    function maxSortedUsers() external view returns (uint256) {
        return _maxSortedUsers;
    }

    function isClaimRewardsPaused() external view returns (bool) {
        return _isClaimRewardsPaused;
    }
}
