// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IERC4626Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {ISupplyVaultBase} from "src/interfaces/extensions/ISupplyVaultBase.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {Types} from "src/libraries/Types.sol";

import {ERC4626UpgradeableSafe, ERC4626Upgradeable, ERC20Upgradeable} from "@morpho-utils/ERC4626UpgradeableSafe.sol";

/// @title SupplyVaultBase.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice ERC4626-upgradeable Tokenized Vault abstract implementation for Morpho-Aave V3.
abstract contract SupplyVaultBase is ISupplyVaultBase, ERC4626UpgradeableSafe, OwnableUpgradeable {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;

    /* IMMUTABLES */

    IMorpho internal immutable _MORPHO; // The main Morpho contract.
    ERC20 internal immutable _MORPHO_TOKEN; // The address of the Morpho Token.
    address internal immutable _RECIPIENT; // The recipient of the rewards that will redistribute them to vault's users.

    /* STORAGE */

    address internal _underlying; // The underlying market to supply to through this vault.
    uint8 internal _maxIterations; // The max iterations to use when this vault interacts with Morpho.

    /* CONSTRUCTOR */

    /// @dev Initializes network-wide immutables.
    /// @param morpho The address of the main Morpho contract.
    /// @param morphoToken The address of the Morpho Token.
    /// @param recipient The recipient of the rewards that will redistribute them to vault's users.
    constructor(address morpho, address morphoToken, address recipient) {
        if (morpho == address(0) || morphoToken == address(0) || recipient == address(0)) {
            revert ZeroAddress();
        }
        _MORPHO = IMorpho(morpho);
        _MORPHO_TOKEN = ERC20(morphoToken);
        _RECIPIENT = recipient;
    }

    /* INITIALIZER */

    /// @dev Initializes the vault.
    /// @param newUnderlying The address of the underlying market to supply through this vault.
    /// @param name The name of the ERC20 token associated to this tokenized vault.
    /// @param symbol The symbol of the ERC20 token associated to this tokenized vault.
    /// @param initialDeposit The amount of the initial deposit used to prevent pricePerShare manipulation.
    /// @param newMaxIterations The max iterations to use when this vault interacts with Morpho.
    function __SupplyVaultBase_init(
        address newUnderlying,
        string calldata name,
        string calldata symbol,
        uint256 initialDeposit,
        uint8 newMaxIterations
    ) internal onlyInitializing {
        __SupplyVaultBase_init_unchained(newUnderlying, newMaxIterations);

        __Ownable_init_unchained();
        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(ERC20Upgradeable(newUnderlying));
        __ERC4626UpgradeableSafe_init_unchained(initialDeposit);
    }

    /// @dev Initializes the vault whithout initializing parent contracts (avoid the double initialization problem).
    /// @param newUnderlying The address of the pool token corresponding to the market to supply through this vault.
    function __SupplyVaultBase_init_unchained(address newUnderlying, uint8 newMaxIterations)
        internal
        onlyInitializing
    {
        _underlying = newUnderlying;
        _maxIterations = newMaxIterations;

        ERC20(newUnderlying).safeApprove(address(_MORPHO), type(uint256).max);
    }

    /* EXTERNAL */

    function MORPHO() external view returns (IMorpho) {
        return _MORPHO;
    }

    function MORPHO_TOKEN() external view returns (ERC20) {
        return _MORPHO_TOKEN;
    }

    function RECIPIENT() external view returns (address) {
        return _RECIPIENT;
    }

    function underlying() external view returns (address) {
        return _underlying;
    }

    /// @notice Transfers the MORPHO rewards to the rewards recipient.
    function transferRewards() external {
        uint256 amount = _MORPHO_TOKEN.balanceOf(address(this));
        address recipient = _RECIPIENT;
        _MORPHO_TOKEN.safeTransfer(recipient, amount);
        emit RewardsTransferred(recipient, amount);
    }

    function setMaxIterations(uint8 newMaxIterations) external onlyOwner {
        _maxIterations = newMaxIterations;
    }

    /* PUBLIC */

    /// @notice The amount of assets in the vault.
    /// @dev The indexes used by this function might not be up-to-date.
    ///      As a consequence, view functions (like `maxWithdraw`) could underestimate the withdrawable amount.
    ///      To redeem all their assets, users are encouraged to use the `redeem` function passing their vault tokens balance.
    function totalAssets() public view virtual override(IERC4626Upgradeable, ERC4626Upgradeable) returns (uint256) {
        return _MORPHO.supplyBalance(_underlying, address(this));
    }

    /* INTERNAL */

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(caller, receiver, assets, shares);
        _MORPHO.supply(_underlying, assets, address(this), uint256(_maxIterations));
    }

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
    uint256[49] private __gap;
}
