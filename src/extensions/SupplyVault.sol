// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IERC4626Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ISupplyVault} from "src/interfaces/extensions/ISupplyVault.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Types} from "src/libraries/Types.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC4626UpgradeableSafe, ERC4626Upgradeable, ERC20Upgradeable} from "@morpho-utils/ERC4626UpgradeableSafe.sol";

/// @title SupplyVault
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable Tokenized Vault implementation for Morpho-Aave V3.
contract SupplyVault is ISupplyVault, ERC4626UpgradeableSafe, OwnableUpgradeable {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;

    /* IMMUTABLES */

    IMorpho internal immutable _MORPHO; // The main Morpho contract.

    /* STORAGE */

    address internal _underlying; // The underlying market to supply to through this vault.
    uint8 internal _maxIterations; // The max iterations to use when this vault interacts with Morpho.
    address internal _recipient; // The recipient of the rewards that will redistribute them to vault's users.

    /* CONSTRUCTOR */

    /// @dev Initializes network-wide immutables.
    /// @param newMorpho The address of the main Morpho contract.
    constructor(address newMorpho) {
        if (newMorpho == address(0)) {
            revert ZeroAddress();
        }
        _MORPHO = IMorpho(newMorpho);
    }

    /* INITIALIZER */

    /// @dev Initializes the vault.
    /// @param newUnderlying The address of the underlying market to supply through this vault to Morpho.
    /// @param newRecipient The recipient to receive skimmed funds.
    /// @param name The name of the ERC20 token associated to this tokenized vault.
    /// @param symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    /// @param newMaxIterations The max iterations to use when this vault interacts with Morpho.
    function initialize(
        address newUnderlying,
        address newRecipient,
        string calldata name,
        string calldata symbol,
        uint256 initialDeposit,
        uint8 newMaxIterations
    ) external initializer {
        __SupplyVault_init_unchained(newUnderlying, newRecipient, newMaxIterations);

        __Ownable_init_unchained();
        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(ERC20Upgradeable(newUnderlying));
        __ERC4626UpgradeableSafe_init_unchained(initialDeposit);
    }

    /// @dev Initializes the vault without initializing parent contracts (avoid the double initialization problem).
    /// @param newUnderlying The address of the underlying token corresponding to the market to supply through this vault.
    /// @param newRecipient The recipient to receive skimmed funds.
    /// @param newMaxIterations The max iterations to use when this vault interacts with Morpho.
    function __SupplyVault_init_unchained(address newUnderlying, address newRecipient, uint8 newMaxIterations)
        internal
        onlyInitializing
    {
        if (newUnderlying == address(0)) revert ZeroAddress();
        _underlying = newUnderlying;
        _recipient = newRecipient;
        _maxIterations = newMaxIterations;

        ERC20(newUnderlying).safeApprove(address(_MORPHO), type(uint256).max);
    }

    /* EXTERNAL */

    /// @notice Transfers the given ERC20 tokens to the vault recipient.
    /// @dev This is meant to be used to transfer rewards that are claimed to the vault or rescue tokens.
    ///      The vault is not intended to hold any ERC20 tokens between calls.
    function skim(address[] calldata tokens) external {
        address recipientMem = _recipient;
        if (recipientMem == address(0)) revert ZeroAddress();
        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = ERC20(token).balanceOf(address(this));
            emit Skimmed(token, recipientMem, amount);
            ERC20(token).safeTransfer(recipientMem, amount);
        }
    }

    /// @notice Sets the max iterations to use when this vault interacts with Morpho.
    function setMaxIterations(uint8 newMaxIterations) external onlyOwner {
        _maxIterations = newMaxIterations;
        emit MaxIterationsSet(newMaxIterations);
    }

    /// @notice Sets the recipient for the skim function.
    function setRecipient(address newRecipient) external onlyOwner {
        _recipient = newRecipient;
        emit RecipientSet(newRecipient);
    }

    /// @notice The address of the Morpho contract this vault utilizes.
    function MORPHO() external view returns (IMorpho) {
        return _MORPHO;
    }

    /// @notice The recipient of any ERC20 tokens skimmed from this contract.
    function recipient() external view returns (address) {
        return _recipient;
    }

    /// @notice The address of the underlying market to supply through this vault to Morpho.
    function underlying() external view returns (address) {
        return _underlying;
    }

    /// @notice The max iterations to use when this vault interacts with Morpho.
    function maxIterations() external view returns (uint8) {
        return _maxIterations;
    }

    /* PUBLIC */

    /// @notice The amount of assets in the vault.
    function totalAssets() public view virtual override(IERC4626Upgradeable, ERC4626Upgradeable) returns (uint256) {
        return _MORPHO.supplyBalance(_underlying, address(this));
    }

    /* INTERNAL */

    /// @dev Used in mint or deposit to deposit the underlying asset to Morpho.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(caller, receiver, assets, shares);
        _MORPHO.supply(_underlying, assets, address(this), uint256(_maxIterations));
    }

    /// @dev Used in redeem or withdraw to withdraw the underlying asset from Morpho.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _MORPHO.withdraw(_underlying, assets, address(this), address(this), uint256(_maxIterations));
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[48] private __gap;
}
