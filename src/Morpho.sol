// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

import "openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Morpho is ERC1155Upgradeable, OwnableUpgradeable {}
