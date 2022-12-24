// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPool, IPoolAddressesProvider} from "./interfaces/Interfaces.sol";

import {Types} from "./libraries/Types.sol";
import {Constants} from "./libraries/Constants.sol";

contract MorphoStorage {
    /// STORAGE ///

    address[] internal _marketsCreated; // Keeps track of the created markets.
    mapping(address => Types.Market) internal _market;
    mapping(address => Types.MarketBalances) internal _marketBalances;
    mapping(address => Types.UserMarkets) internal _userMarkets; // The markets entered by a user as a bitmask.

    uint256 internal _maxSortedUsers; // The max number of users to sort in the data structure.

    IPoolAddressesProvider internal _addressesProvider;
    IPool internal _pool;
    address internal _entryPositionsManager;
    address internal _exitPositionsManager;
    // IInterestRatesManager internal _interestRatesManager;
    // IRewardsController internal _rewardsController;
    // IIncentivesVault internal _incentivesVault;
    // IRewardsManager internal _rewardsManager;

    address internal _treasuryVault;
    bool internal _isClaimRewardsPaused; // Whether claiming rewards is paused or not.
}
