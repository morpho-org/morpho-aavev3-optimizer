// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types, Events, Errors, MarketLib} from "./libraries/Libraries.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGettersAndSetters is MorphoInternal {
    using MarketLib for Types.MarketBalances;
    using MarketLib for Types.Market;

    /// STORAGE ///

    function market(address poolToken) external view returns (Types.Market memory) {
        return _market[poolToken];
    }

    function scaledPoolSupplyBalance(address poolToken, address user) external view returns (uint256) {
        return _marketBalances[poolToken].scaledPoolSupplyBalance(user);
    }

    function scaledP2PSupplyBalance(address poolToken, address user) external view returns (uint256) {
        return _marketBalances[poolToken].scaledP2PSupplyBalance(user);
    }

    function scaledPoolBorrowBalance(address poolToken, address user) external view returns (uint256) {
        return _marketBalances[poolToken].scaledPoolBorrowBalance(user);
    }

    function scaledP2PBorrowBalance(address poolToken, address user) external view returns (uint256) {
        return _marketBalances[poolToken].scaledP2PBorrowBalance(user);
    }

    function scaledCollateralBalance(address poolToken, address user) external view returns (uint256) {
        return _marketBalances[poolToken].scaledCollateralBalance(user);
    }

    function userMarkets(address user) external view returns (Types.UserMarkets memory) {
        return _userMarkets[user];
    }

    function maxSortedUsers() external view returns (uint256) {
        return _maxSortedUsers;
    }

    function isClaimRewardsPaused() external view returns (bool) {
        return _isClaimRewardsPaused;
    }

    /// UTILITY ///

    function decodeId(uint256 id) external pure returns (address poolToken, Types.PositionType positionType) {
        return _decodeId(id);
    }

    /// ERC1155 ///

    function balanceOf(address user, uint256 id) external view returns (uint256) {
        (address poolToken, Types.PositionType positionType) = _decodeId(id);
        Types.MarketBalances storage marketBalances = _marketBalances[poolToken];

        if (positionType == Types.PositionType.COLLATERAL) {
            return marketBalances.scaledCollateralBalance(user);
        } else if (positionType == Types.PositionType.SUPPLY) {
            return marketBalances.scaledP2PSupplyBalance(user) + marketBalances.scaledPoolSupplyBalance(user); // TODO: take into account indexes.
        } else if (positionType == Types.PositionType.BORROW) {
            return marketBalances.scaledP2PBorrowBalance(user) + marketBalances.scaledPoolBorrowBalance(user); // TODO: take into account indexes.
        } else {
            return 0;
        }
    }
}
