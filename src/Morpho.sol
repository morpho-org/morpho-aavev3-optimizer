// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Types} from "./libraries/Types.sol";

import {ERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Morpho is ERC1155Upgradeable, OwnableUpgradeable {
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    /// STORAGE ///

    mapping(address => Types.Market) internal markets;

    /// EXTERNAL ///

    function supply(
        address _underlying,
        uint256 _amount,
        address _from,
        address _for,
        uint256 _nbOfLoops,
        Types.PositionType _type
    ) external returns (uint256 supplied) {}

    function borrow(address _underlying, uint256 _amount, address _from, address _to, uint256 _nbOfLoops)
        external
        returns (uint256 borrowed)
    {}

    function repay(address _underlying, uint256 _amount, address _from, address _for)
        external
        returns (uint256 repaid)
    {}

    function withdraw(address _underlying, uint256 _amount, address _from, address _to)
        external
        returns (uint256 withdrawn)
    {}

    function liquidate(address _collateralUnderlying, address _borrowedUnderlying, address _user, uint256 _amount)
        external
        returns (uint256 repaid, uint256 seized)
    {}

    /// PUBLIC ///

    function decodeId(uint256 _id) public pure returns (address underlying, Types.PositionType positionType) {
        underlying = address(uint160(_id));
        positionType = Types.PositionType(_id & 0xf);
    }

    /// ERC1155 ///

    function balanceOf(address _user, uint256 _id) public view virtual override returns (uint256) {
        (address underlying, Types.PositionType positionType) = decodeId(_id);
        Types.Market storage market = markets[underlying];

        if (positionType == Types.PositionType.COLLATERAL) {
            return market.collateralScaledBalance[_user];
        } else if (positionType == Types.PositionType.SUPPLY) {
            return market.suppliersP2P.getValueOf(_user) + market.suppliersP2P.getValueOf(_user); // TODO: take into account indexes.
        } else if (positionType == Types.PositionType.BORROW) {
            return market.borrowersP2P.getValueOf(_user) + market.borrowersP2P.getValueOf(_user); // TODO: take into account indexes.
        } else {
            return 0;
        }
    }
}
