// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {ISupplyVaultBase} from "src/interfaces/extensions/ISupplyVaultBase.sol";

interface ISupplyVault is ISupplyVaultBase {
    function skim(address[] memory tokens) external;
}
