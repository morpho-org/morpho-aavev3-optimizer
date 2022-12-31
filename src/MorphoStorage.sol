// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPool, IPoolAddressesProvider} from "./interfaces/aave/IPool.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {Types} from "./libraries/Types.sol";
import {Constants} from "./libraries/Constants.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MorphoStorage is Initializable, OwnableUpgradeable {
    /// STORAGE ///

    address[] internal _marketsCreated; // Keeps track of the created markets.
    mapping(address => Types.Market) internal _market;
    mapping(address => Types.MarketBalances) internal _marketBalances;
    mapping(address => EnumerableSet.AddressSet) internal _userCollaterals; // The markets entered by a user.
    mapping(address => EnumerableSet.AddressSet) internal _userBorrows; // The markets entered by a user.

    uint256 internal _maxSortedUsers; // The max number of users to sort in the data structure.
    Types.MaxLoops internal _defaultMaxLoops;

    IPoolAddressesProvider internal _addressesProvider;
    IPool internal _pool;
    address internal _entryPositionsManager;
    address internal _exitPositionsManager;
    // IInterestRatesManager internal _interestRatesManager;
    // IRewardsController internal _rewardsController;
    // IRewardsManager internal _rewardsManager;

    address internal _treasuryVault;
    bool internal _isClaimRewardsPaused; // Whether claiming rewards is paused or not.
}
