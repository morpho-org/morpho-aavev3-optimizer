// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoGetters} from "./interfaces/IMorpho.sol";

import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {Types} from "./libraries/Types.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGetters is IMorphoGetters, MorphoInternal {
    using MarketBalanceLib for Types.MarketBalances;

    /// STORAGE ///

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

    function maxSortedUsers() external view returns (uint256) {
        return _maxSortedUsers;
    }

    function isClaimRewardsPaused() external view returns (bool) {
        return _isClaimRewardsPaused;
    }

    /// UTILITY ///

    function decodeId(uint256 id) external pure returns (address underlying, Types.PositionType positionType) {
        return _decodeId(id);
    }

    /// ERC1155 ///

    function balanceOf(address user, uint256 id) external view returns (uint256) {
        (address underlying, Types.PositionType positionType) = _decodeId(id);
        Types.MarketBalances storage marketBalances = _marketBalances[underlying];

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
