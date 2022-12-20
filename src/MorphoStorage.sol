// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPool, IPoolAddressesProvider} from "./interfaces/Interfaces.sol";

import {Types} from "./libraries/Types.sol";
import {Constants} from "./libraries/Constants.sol";

contract MorphoStorage {
    /// CONSTANTS ///

    uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = Constants.DEFAULT_LIQUIDATION_CLOSE_FACTOR;
    uint256 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = Constants.HEALTH_FACTOR_LIQUIDATION_THRESHOLD; // Health factor below which the positions can be liquidated.
    uint256 internal constant MAX_NB_OF_MARKETS = Constants.MAX_NB_OF_MARKETS;
    uint256 internal constant MAX_LIQUIDATION_CLOSE_FACTOR = Constants.MAX_LIQUIDATION_CLOSE_FACTOR; // 100% in basis points.
    uint256 internal constant MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD =
        Constants.MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD; // Health factor below which the positions can be liquidated, whether or not the price oracle sentinel allows the liquidation.
    bytes32 internal constant BORROWING_MASK = Constants.BORROWING_MASK;
    bytes32 internal constant ONE = Constants.ONE;

    /// STORAGE ///

    address[] internal _marketsCreated; // Keeps track of the created markets.
    mapping(address => Types.Market) internal _market;
    mapping(address => Types.MarketBalances) internal _marketBalances;
    mapping(address => Types.UserMarkets) internal _userMarkets; // The markets entered by a user as a bitmask.

    uint256 internal _maxSortedUsers; // The max number of users to sort in the data structure.

    IPoolAddressesProvider internal _addressesProvider;
    IPool internal _pool;
    // IEntryPositionsManager internal _entryPositionsManager;
    // IExitPositionsManager internal _exitPositionsManager;
    // IInterestRatesManager internal _interestRatesManager;
    // IRewardsController internal _rewardsController;
    // IIncentivesVault internal _incentivesVault;
    // IRewardsManager internal _rewardsManager;

    address internal _treasuryVault;
    bool internal _isClaimRewardsPaused; // Whether claiming rewards is paused or not.
}
