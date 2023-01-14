// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoGetters} from "./interfaces/IMorpho.sol";

import {Types} from "./libraries/Types.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGetters is IMorphoGetters, MorphoInternal {
    using WadRayMath for uint256;
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;

    /// STORAGE ///

    function POOL() external view returns (address) {
        return address(_POOL);
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return address(_ADDRESSES_PROVIDER);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    function market(address underlying) external view returns (Types.Market memory) {
        return _market[underlying];
    }

    function marketsCreated() external view returns (address[] memory) {
        return _marketsCreated;
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

    function supplyBalance(address underlying, address user) external view returns (uint256) {
        Types.MarketSideIndexes256 memory indexes = _market[underlying].getSupplyIndexes();
        return _marketBalances[underlying].scaledPoolSupplyBalance(user).rayMul(indexes.poolIndex)
            + _marketBalances[underlying].scaledP2PSupplyBalance(user).rayMul(indexes.p2pIndex);
    }

    function borrowBalance(address underlying, address user) external view returns (uint256) {
        Types.MarketSideIndexes256 memory indexes = _market[underlying].getBorrowIndexes();
        return _marketBalances[underlying].scaledPoolBorrowBalance(user).rayMul(indexes.poolIndex)
            + _marketBalances[underlying].scaledP2PBorrowBalance(user).rayMul(indexes.p2pIndex);
    }

    function collateralBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledCollateralBalance(user).rayMul(
            _market[underlying].indexes.supply.poolIndex
        );
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

    function defaultMaxLoops() external view returns (Types.MaxLoops memory) {
        return _defaultMaxLoops;
    }

    function positionsManager() external view returns (address) {
        return _positionsManager;
    }

    function rewardsManager() external view returns (address) {
        return address(_rewardsManager);
    }

    function treasuryVault() external view returns (address) {
        return _treasuryVault;
    }

    function isClaimRewardsPaused() external view returns (bool) {
        return _isClaimRewardsPaused;
    }

    function updatedIndexes(address underlying) external view returns (Types.Indexes256 memory) {
        return _computeIndexes(underlying);
    }

    function liquidityData(address underlying, address user, uint256 amountWithdrawn, uint256 amountBorrowed)
        external
        view
        returns (Types.LiquidityData memory)
    {
        return _liquidityData(underlying, user, amountWithdrawn, amountBorrowed);
    }

    function healthFactor(address user) external view returns (uint256) {
        return _getUserHealthFactor(address(0), user, 0);
    }
}
