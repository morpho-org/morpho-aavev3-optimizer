// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {ISupplyVaultBase} from "src/interfaces/extensions/ISupplyVaultBase.sol";

interface ISupplyVault is ISupplyVaultBase {
    /* EVENTS */

    /// @notice Emitted when tokens are skimmed to `recipient`.
    /// @param token The token being skimmed.
    /// @param recipient The recipient.
    /// @param amount The amount of rewards transferred.
    event Skimmed(address token, address recipient, uint256 amount);

    /* EXTERNAL */

    function skim(address[] calldata tokens) external;
}
