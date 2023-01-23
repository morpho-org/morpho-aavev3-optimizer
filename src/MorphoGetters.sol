// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoGetters} from "./interfaces/IMorpho.sol";

import {Types} from "./libraries/Types.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

/// @title MorphoGetters
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Abstract contract exposing all accessible getters.
abstract contract MorphoGetters is IMorphoGetters, MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// STORAGE ///

    /// @notice Returns the pool address.
    function POOL() external view returns (address) {
        return address(_POOL);
    }

    /// @notice Returns the addresses provider address.
    function ADDRESSES_PROVIDER() external view returns (address) {
        return address(_ADDRESSES_PROVIDER);
    }

    /// @notice Returns the domain separator of the EIP712.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    /// @notice Returns the market data.
    function market(address underlying) external view returns (Types.Market memory) {
        return _market[underlying];
    }

    /// @notice Returns the list of the markets created.
    function marketsCreated() external view returns (address[] memory) {
        return _marketsCreated;
    }

    /// @notice Returns the scaled pool supply balance of `user` on the `underlying` market (in ray).
    function scaledPoolSupplyBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledPoolSupplyBalance(user);
    }

    /// @notice Returns the scaled peer-to-peer supply balance of `user` on the `underlying` market (in ray).
    function scaledP2PSupplyBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledP2PSupplyBalance(user);
    }

    /// @notice Returns the scaled pool borrow balance of `user` on the `underlying` market (in ray).
    function scaledPoolBorrowBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledPoolBorrowBalance(user);
    }

    /// @notice Returns the scaled peer-to-peer borrow balance of `user` on the `underlying` market (in ray).
    function scaledP2PBorrowBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledP2PBorrowBalance(user);
    }

    /// @notice Returns the scaled pool supply collateral balance of `user` on the `underlying` market (in ray).
    function scaledCollateralBalance(address underlying, address user) external view returns (uint256) {
        return _marketBalances[underlying].scaledCollateralBalance(user);
    }

    /// @notice Returns the total supply balance of `user` on the `underlying` market (in `underlying`).
    function supplyBalance(address underlying, address user) external view returns (uint256) {
        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);

        return _getUserSupplyBalanceFromIndexes(underlying, user, indexes.supply);
    }

    /// @notice Returns the total borrow balance of `user` on the `underlying` market (in `underlying`).
    function borrowBalance(address underlying, address user) external view returns (uint256) {
        (, Types.Indexes256 memory indexes) = _computeIndexes(underlying);

        return _getUserBorrowBalanceFromIndexes(underlying, user, indexes.borrow);
    }

    /// @notice Returns the supply collateral balance of `user` on the `underlying` market (in `underlying`).
    function collateralBalance(address underlying, address user) external view returns (uint256) {
        return _getUserCollateralBalanceFromIndex(underlying, user, _POOL.getReserveNormalizedIncome(underlying));
    }

    /// @notice Returns the list of collateral underlyings of `user`.
    function userCollaterals(address user) external view returns (address[] memory) {
        return _userCollaterals[user].values();
    }

    /// @notice Returns the list of borrowed underlyings of `user`.
    function userBorrows(address user) external view returns (address[] memory) {
        return _userBorrows[user].values();
    }

    /// @notice Returns whether `manager` is a manager of `delegator`.
    function isManaging(address delegator, address manager) external view returns (bool) {
        return _isManaging[delegator][manager];
    }

    /// @notice Returns the nonce of `user` for the manager approval signature.
    function userNonce(address user) external view returns (uint256) {
        return _userNonce[user];
    }

    /// @notice Returns the default max loops.
    function defaultMaxLoops() external view returns (Types.MaxLoops memory) {
        return _defaultMaxLoops;
    }

    /// @notice Returns the address of the positions manager.
    function positionsManager() external view returns (address) {
        return _positionsManager;
    }

    /// @notice Returns the address of the rewards manager.
    function rewardsManager() external view returns (address) {
        return address(_rewardsManager);
    }

    /// @notice Returns the address of the treasury vault.
    function treasuryVault() external view returns (address) {
        return _treasuryVault;
    }

    /// @notice Returns whether the claim rewards is paused or not.
    function isClaimRewardsPaused() external view returns (bool) {
        return _isClaimRewardsPaused;
    }

    /// @notice Returns the updated indexes (peer-to-peer and pool).
    function updatedIndexes(address underlying) external view returns (Types.Indexes256 memory indexes) {
        (, indexes) = _computeIndexes(underlying);
    }

    /// @notice Returns the hypothetical liquidity data of `user`.
    /// @param underlying The address of the underlying asset to borrow.
    /// @param user The address of the user to get liquidity data for.
    /// @param amountWithdrawn The hypothetical amount to withdraw on the `underlying` market.
    /// @param amountBorrowed The hypothetical amount to borrow on the `underlying` market.
    /// @return The hypothetical liquidaty data of `user`.
    function liquidityData(address underlying, address user, uint256 amountWithdrawn, uint256 amountBorrowed)
        external
        view
        returns (Types.LiquidityData memory)
    {
        return _liquidityData(underlying, user, amountWithdrawn, amountBorrowed);
    }
}
