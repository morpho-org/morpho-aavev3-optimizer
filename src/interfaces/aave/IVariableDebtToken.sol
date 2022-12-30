// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {DataTypes} from "../../libraries/aave/DataTypes.sol";

interface IVariableDebtToken {
    function scaledBalanceOf(address) external view returns (uint256);
}
