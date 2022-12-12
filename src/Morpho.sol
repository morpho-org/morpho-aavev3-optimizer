// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Types} from "./libraries/Types.sol";

import {ERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Morpho is ERC1155Upgradeable, OwnableUpgradeable {
    using ThreeHeapOrdering for ThreeHeapOrdering.Heap;

    /// STORAGE ///

    mapping(address => Types.Market) internal markets;

    /// EXTERNAL ///

    function supply(address _underlying, uint256 _amount, address _from, address _to, uint256 _nbOfLoops)
        external
        returns (uint256 supplied)
    {}

    function borrow(address _underlying, uint256 _amount, address _from, address _to, uint256 _nbOfLoops)
        external
        returns (uint256 borrowed)
    {}

    function repay(address _underlying, uint256 _amount, address _from, address _to, uint256 _nbOfLoops)
        external
        returns (uint256 repaid)
    {}

    function witdhraw(address _underlying, uint256 _amount, address _from, address _to, uint256 _nbOfLoops)
        external
        returns (uint256 withdrawn)
    {}

    function liquidate(address _collateralUnderlying, address _borrowedUnderlying, address _user, uint256 _amount)
        external
        returns (uint256 repaid, uint256 seized)
    {}
}
