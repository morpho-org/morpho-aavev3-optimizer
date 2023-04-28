// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ISupplyVault} from "src/interfaces/extensions/ISupplyVault.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {SupplyVaultBase} from "src/extensions/SupplyVaultBase.sol";

/// @title SupplyVault.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable Tokenized Vault implementation for Morpho-Aave V3.
contract SupplyVault is ISupplyVault, SupplyVaultBase {
    using SafeTransferLib for ERC20;

    /* CONSTRUCTOR */

    /// @dev Initializes network-wide immutables.
    /// @param morpho The address of the main Morpho contract.
    /// @param morphoToken The address of the Morpho Token.
    /// @param recipient The recipient of the rewards that will redistribute them to vault's users.
    constructor(address morpho, address morphoToken, address recipient)
        SupplyVaultBase(morpho, morphoToken, recipient)
    {}

    /* INITIALIZER */

    /// @dev Initializes the vault.
    /// @param newUnderlying The address of the underlying market to supply through this vault to Morpho.
    /// @param name The name of the ERC20 token associated to this tokenized vault.
    /// @param symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    /// @param newMaxIterations The max iterations to use when this vault interacts with Morpho.
    function initialize(
        address newUnderlying,
        string calldata name,
        string calldata symbol,
        uint256 initialDeposit,
        uint8 newMaxIterations
    ) external initializer {
        __SupplyVaultBase_init(newUnderlying, name, symbol, initialDeposit, newMaxIterations);
    }

    /// @notice Transfers any underlyings to the vault recipient.
    /// @dev This is meant to be used to transfer rewards that are claimed to the vault. The vault does not hold any underlying tokens between calls.
    function skim(address[] calldata tokens) external {
        for (uint256 i; i < tokens.length; i++) {
            address recipient = _RECIPIENT;
            uint256 amount = ERC20(tokens[i]).balanceOf(address(this));
            emit Skimmed(tokens[i], recipient, amount);
            ERC20(tokens[i]).safeTransfer(_RECIPIENT, amount);
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}
