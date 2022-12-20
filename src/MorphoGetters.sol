// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IERC1155, IPoolAddressesProvider, IPool} from "./interfaces/Interfaces.sol";

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

abstract contract MorphoGetters is IERC1155, MorphoInternal {
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

    function decodeId(uint256 id) external view returns (address, Types.PositionType) {
        return _decodeId(id);
    }

    /// ERC1155 ///

    /// @inheritdoc IERC1155
    function balanceOf(address _owner, uint256 _id) public view returns (uint256) {
        (address underlying, Types.PositionType positionType) = _decodeId(_id);

        return _balanceOf(_owner, underlying, positionType);
    }

    /// @inheritdoc IERC1155
    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids)
        external
        view
        returns (uint256[] memory batchBalances)
    {
        if (_owners.length != _ids.length) revert Errors.LengthMismatch();

        batchBalances = new uint256[](_owners.length);

        for (uint256 i; i < _owners.length; ++i) {
            batchBalances[i] = balanceOf(_owners[i], _ids[i]);
        }
    }

    /// @inheritdoc IERC1155
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        uint256 nbMarkets = _marketsCreated.length;

        for (uint256 i; i < nbMarkets; ++i) {
            if (!_isApprovedForBy[_marketsCreated[i]][_owner][_operator]) return false;
        }

        return true;
    }
}
