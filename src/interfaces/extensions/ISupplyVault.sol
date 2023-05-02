// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC4626Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ERC20} from "@solmate/utils/SafeTransferLib.sol";

interface ISupplyVault is IERC4626Upgradeable {
    /* EVENTS */

    /// @notice Emitted when max iterations is set.
    /// @param maxIterations The max iterations.
    event MaxIterationsSet(uint8 maxIterations);

    /// @notice Emitted when the recipient is set.
    /// @param recipient The recipient.
    event RecipientSet(address recipient);

    /// @notice Emitted when tokens are skimmed to `recipient`.
    /// @param token The token being skimmed.
    /// @param recipient The recipient.
    /// @param amount The amount of rewards transferred.
    event Skimmed(address token, address recipient, uint256 amount);

    /* ERRORS */

    /// @notice Thrown when the zero address is passed as input or is the recipient address when calling `transferRewards`.
    error ZeroAddress();

    /* EXTERNAL */

    function MORPHO() external view returns (IMorpho);

    function recipient() external view returns (address);

    function underlying() external view returns (address);

    function maxIterations() external view returns (uint8);

    function skim(address[] calldata tokens) external;

    function setMaxIterations(uint8 newMaxIterations) external;

    function setRecipient(address newRecipient) external;
}
