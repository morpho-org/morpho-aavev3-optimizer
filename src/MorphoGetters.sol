// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoGetters} from "./interfaces/IMorpho.sol";

import {Types} from "./libraries/Types.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGetters is IMorphoGetters, MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;

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
        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);

        return _getUserSupplyBalanceFromIndexes(underlying, user, indexes.supply);
    }

    function borrowBalance(address underlying, address user) external view returns (uint256) {
        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);

        return _getUserSupplyBalanceFromIndexes(underlying, user, indexes.borrow);
    }

    function collateralBalance(address underlying, address user) external view returns (uint256) {
        return _getUserCollateralBalanceFromIndex(underlying, user, _POOL.getReserveNormalizedIncome(underlying));
    }

    function userCollaterals(address user) external view returns (address[] memory) {
        return _userCollaterals[user].values();
    }

    function userBorrows(address user) external view returns (address[] memory) {
        return _userBorrows[user].values();
    }

    function isManaging(address delegator, address manager) external view returns (bool) {
        return _isManaging[delegator][manager];
    }

    function userNonce(address user) external view returns (uint256) {
        return _userNonce[user];
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

    function updatedIndexes(address underlying) external view returns (Types.Indexes256 memory indexes) {
        (, indexes) = _computeIndexes(underlying);
    }

    function liquidityData(address underlying, address user, uint256 amountWithdrawn, uint256 amountBorrowed)
        external
        view
        returns (Types.LiquidityData memory)
    {
        return _liquidityData(underlying, user, amountWithdrawn, amountBorrowed);
    }
}
