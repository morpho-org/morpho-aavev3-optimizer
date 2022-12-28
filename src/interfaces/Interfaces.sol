// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC1155} from "./IERC1155.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";

// These cannot be imported from aave's repo because they depend on solidity v0.8.10.
import {IAToken} from "./aave/IAToken.sol";
import {IVariableDebtToken} from "./aave/IVariableDebtToken.sol";
import {IPoolAddressesProvider, IPool} from "./aave/IPool.sol";
