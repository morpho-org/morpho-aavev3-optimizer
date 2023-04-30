// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC4626Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ERC20} from "@solmate/utils/SafeTransferLib.sol";

interface ISupplyVaultBase is IERC4626Upgradeable {
    /* EVENTS */

    /// @notice Emitted when max iterations is set.
    /// @param maxIterations The max iterations.
    event MaxIterationsSet(uint8 maxIterations);

    /* ERRORS */

    /// @notice Thrown when the zero address is passed as input or is the recipient address when calling `transferRewards`.
    error ZeroAddress();

    /* FUNCTIONS */

    function MORPHO() external view returns (IMorpho);

    function RECIPIENT() external view returns (address);

    function underlying() external view returns (address);

    function maxIterations() external view returns (uint8);
}
