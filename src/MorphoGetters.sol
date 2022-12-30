// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPoolAddressesProvider, IPool} from "./interfaces/aave/IPool.sol";

import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";

import {DataTypes} from "./libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoGetters is MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

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

    function nonces(address user) external view returns (uint256) {
        return _nonces[user];
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
