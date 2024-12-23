// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/**
 * @title IPoolConfigurator
 * @author Aave
 * @notice Defines the basic interface for a Pool configurator.
 */
interface IPoolConfigurator {
    /**
     * @dev Emitted when a reserve is initialized.
     * @param asset The address of the underlying asset of the reserve
     * @param aToken The address of the associated aToken contract
     * @param stableDebtToken The address of the associated stable rate debt token
     * @param variableDebtToken The address of the associated variable rate debt token
     * @param interestRateStrategyAddress The address of the interest rate strategy for the reserve
     */
    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        address stableDebtToken,
        address variableDebtToken,
        address interestRateStrategyAddress
    );

    /**
     * @dev Emitted when borrowing is enabled or disabled on a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param enabled True if borrowing is enabled, false otherwise
     */
    event ReserveBorrowing(address indexed asset, bool enabled);

    /**
     * @dev Emitted when flashloans are enabled or disabled on a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param enabled True if flashloans are enabled, false otherwise
     */
    event ReserveFlashLoaning(address indexed asset, bool enabled);

    /**
     * @dev Emitted when the collateralization risk parameters for the specified asset are updated.
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset
     */
    event CollateralConfigurationChanged(
        address indexed asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus
    );

    /**
     * @dev Emitted when stable rate borrowing is enabled or disabled on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param enabled True if stable rate borrowing is enabled, false otherwise
     */
    event ReserveStableRateBorrowing(address indexed asset, bool enabled);

    /**
     * @dev Emitted when a reserve is activated or deactivated
     * @param asset The address of the underlying asset of the reserve
     * @param active True if reserve is active, false otherwise
     */
    event ReserveActive(address indexed asset, bool active);

    /**
     * @dev Emitted when a reserve is frozen or unfrozen
     * @param asset The address of the underlying asset of the reserve
     * @param frozen True if reserve is frozen, false otherwise
     */
    event ReserveFrozen(address indexed asset, bool frozen);

    /**
     * @dev Emitted when a reserve is paused or unpaused
     * @param asset The address of the underlying asset of the reserve
     * @param paused True if reserve is paused, false otherwise
     */
    event ReservePaused(address indexed asset, bool paused);

    /**
     * @dev Emitted when a reserve is dropped.
     * @param asset The address of the underlying asset of the reserve
     */
    event ReserveDropped(address indexed asset);

    /**
     * @dev Emitted when a reserve factor is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldReserveFactor The old reserve factor, expressed in bps
     * @param newReserveFactor The new reserve factor, expressed in bps
     */
    event ReserveFactorChanged(address indexed asset, uint256 oldReserveFactor, uint256 newReserveFactor);

    /**
     * @dev Emitted when the borrow cap of a reserve is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldBorrowCap The old borrow cap
     * @param newBorrowCap The new borrow cap
     */
    event BorrowCapChanged(address indexed asset, uint256 oldBorrowCap, uint256 newBorrowCap);

    /**
     * @dev Emitted when the supply cap of a reserve is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldSupplyCap The old supply cap
     * @param newSupplyCap The new supply cap
     */
    event SupplyCapChanged(address indexed asset, uint256 oldSupplyCap, uint256 newSupplyCap);

    /**
     * @dev Emitted when the liquidation protocol fee of a reserve is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldFee The old liquidation protocol fee, expressed in bps
     * @param newFee The new liquidation protocol fee, expressed in bps
     */
    event LiquidationProtocolFeeChanged(address indexed asset, uint256 oldFee, uint256 newFee);

    /**
     * @dev Emitted when the unbacked mint cap of a reserve is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldUnbackedMintCap The old unbacked mint cap
     * @param newUnbackedMintCap The new unbacked mint cap
     */
    event UnbackedMintCapChanged(address indexed asset, uint256 oldUnbackedMintCap, uint256 newUnbackedMintCap);

    /* @dev Emitted when an collateral configuration of an asset in an eMode is changed.
    * @param asset The address of the underlying asset of the reserve
    * @param categoryId The eMode category
    * @param collateral True if the asset is enabled as collateral in the eMode, false otherwise.
    */
    event AssetCollateralInEModeChanged(address indexed asset, uint8 categoryId, bool collateral);

    /**
     * @dev Emitted when the borrowable configuration of an asset in an eMode changed.
     * @param asset The address of the underlying asset of the reserve
     * @param categoryId The eMode category
     * @param borrowable True if the asset is enabled as borrowable in the eMode, false otherwise.
     */
    event AssetBorrowableInEModeChanged(address indexed asset, uint8 categoryId, bool borrowable);

    /**
     * @dev Emitted when a new eMode category is added.
     * @param categoryId The new eMode category id
     * @param ltv The ltv for the asset category in eMode
     * @param liquidationThreshold The liquidationThreshold for the asset category in eMode
     * @param liquidationBonus The liquidationBonus for the asset category in eMode
     * @param label A human readable identifier for the category
     */
    event EModeCategoryAdded(
        uint8 indexed categoryId, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, string label
    );

    /**
     * @dev Emitted when a reserve interest strategy contract is updated.
     * @param asset The address of the underlying asset of the reserve
     * @param oldStrategy The address of the old interest strategy contract
     * @param newStrategy The address of the new interest strategy contract
     */
    event ReserveInterestRateStrategyChanged(address indexed asset, address oldStrategy, address newStrategy);

    /**
     * @dev Emitted when an aToken implementation is upgraded.
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The aToken proxy address
     * @param implementation The new aToken implementation
     */
    event ATokenUpgraded(address indexed asset, address indexed proxy, address indexed implementation);

    /**
     * @dev Emitted when the implementation of a variable debt token is upgraded.
     * @param asset The address of the underlying asset of the reserve
     * @param proxy The variable debt token proxy address
     * @param implementation The new aToken implementation
     */
    event VariableDebtTokenUpgraded(address indexed asset, address indexed proxy, address indexed implementation);

    /**
     * @dev Emitted when the debt ceiling of an asset is set.
     * @param asset The address of the underlying asset of the reserve
     * @param oldDebtCeiling The old debt ceiling
     * @param newDebtCeiling The new debt ceiling
     */
    event DebtCeilingChanged(address indexed asset, uint256 oldDebtCeiling, uint256 newDebtCeiling);

    /**
     * @dev Emitted when the the siloed borrowing state for an asset is changed.
     * @param asset The address of the underlying asset of the reserve
     * @param oldState The old siloed borrowing state
     * @param newState The new siloed borrowing state
     */
    event SiloedBorrowingChanged(address indexed asset, bool oldState, bool newState);

    /**
     * @dev Emitted when the bridge protocol fee is updated.
     * @param oldBridgeProtocolFee The old protocol fee, expressed in bps
     * @param newBridgeProtocolFee The new protocol fee, expressed in bps
     */
    event BridgeProtocolFeeUpdated(uint256 oldBridgeProtocolFee, uint256 newBridgeProtocolFee);

    /**
     * @dev Emitted when the total premium on flashloans is updated.
     * @param oldFlashloanPremiumTotal The old premium, expressed in bps
     * @param newFlashloanPremiumTotal The new premium, expressed in bps
     */
    event FlashloanPremiumTotalUpdated(uint128 oldFlashloanPremiumTotal, uint128 newFlashloanPremiumTotal);

    /**
     * @dev Emitted when the part of the premium that goes to protocol is updated.
     * @param oldFlashloanPremiumToProtocol The old premium, expressed in bps
     * @param newFlashloanPremiumToProtocol The new premium, expressed in bps
     */
    event FlashloanPremiumToProtocolUpdated(
        uint128 oldFlashloanPremiumToProtocol, uint128 newFlashloanPremiumToProtocol
    );

    /**
     * @dev Emitted when the reserve is set as borrowable/non borrowable in isolation mode.
     * @param asset The address of the underlying asset of the reserve
     * @param borrowable True if the reserve is borrowable in isolation, false otherwise
     */
    event BorrowableInIsolationChanged(address asset, bool borrowable);

    /**
     * @notice Configures borrowing on a reserve.
     * @dev Can only be disabled (set to false) if stable borrowing is disabled
     * @param asset The address of the underlying asset of the reserve
     * @param enabled True if borrowing needs to be enabled, false otherwise
     */
    function setReserveBorrowing(address asset, bool enabled) external;

    /**
     * @notice Configures the reserve collateralization parameters.
     * @dev All the values are expressed in bps. A value of 10000, results in 100.00%
     * @dev The `liquidationBonus` is always above 100%. A value of 105% means the liquidator will receive a 5% bonus
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset
     */
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;

    /**
     * @notice Enable or disable flashloans on a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param enabled True if flashloans need to be enabled, false otherwise
     */
    function setReserveFlashLoaning(address asset, bool enabled) external;

    /**
     * @notice Activate or deactivate a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param active True if the reserve needs to be active, false otherwise
     */
    function setReserveActive(address asset, bool active) external;

    /**
     * @notice Freeze or unfreeze a reserve. A frozen reserve doesn't allow any new supply, borrow
     * or rate swap but allows repayments, liquidations, rate rebalances and withdrawals.
     * @param asset The address of the underlying asset of the reserve
     * @param freeze True if the reserve needs to be frozen, false otherwise
     */
    function setReserveFreeze(address asset, bool freeze) external;

    /**
     * @notice Sets the borrowable in isolation flag for the reserve.
     * @dev When this flag is set to true, the asset will be borrowable against isolated collaterals and the
     * borrowed amount will be accumulated in the isolated collateral's total debt exposure
     * @dev Only assets of the same family (e.g. USD stablecoins) should be borrowable in isolation mode to keep
     * consistency in the debt ceiling calculations
     * @param asset The address of the underlying asset of the reserve
     * @param borrowable True if the asset should be borrowable in isolation, false otherwise
     */
    function setBorrowableInIsolation(address asset, bool borrowable) external;

    /**
     * @notice Pauses a reserve. A paused reserve does not allow any interaction (supply, borrow, repay,
     * swap interest rate, liquidate, atoken transfers).
     * @param asset The address of the underlying asset of the reserve
     * @param paused True if pausing the reserve, false if unpausing
     */
    function setReservePause(address asset, bool paused) external;

    /**
     * @notice Updates the reserve factor of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newReserveFactor The new reserve factor of the reserve
     */
    function setReserveFactor(address asset, uint256 newReserveFactor) external;

    /**
     * @notice Sets the interest rate strategy of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newRateStrategyAddress The address of the new interest strategy contract
     */
    function setReserveInterestRateStrategyAddress(address asset, address newRateStrategyAddress) external;

    /**
     * @notice Pauses or unpauses all the protocol reserves. In the paused state all the protocol interactions
     * are suspended.
     * @param paused True if protocol needs to be paused, false otherwise
     */
    function setPoolPause(bool paused) external;

    /**
     * @notice Updates the borrow cap of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newBorrowCap The new borrow cap of the reserve
     */
    function setBorrowCap(address asset, uint256 newBorrowCap) external;

    /**
     * @notice Updates the supply cap of a reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newSupplyCap The new supply cap of the reserve
     */
    function setSupplyCap(address asset, uint256 newSupplyCap) external;

    /**
     * @notice Updates the liquidation protocol fee of reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newFee The new liquidation protocol fee of the reserve, expressed in bps
     */
    function setLiquidationProtocolFee(address asset, uint256 newFee) external;

    /**
     * @notice Updates the unbacked mint cap of reserve.
     * @param asset The address of the underlying asset of the reserve
     * @param newUnbackedMintCap The new unbacked mint cap of the reserve
     */
    function setUnbackedMintCap(address asset, uint256 newUnbackedMintCap) external;

    /**
     * @notice Enables/disables an asset to be borrowable in a selected eMode.
     * - eMode.borrowable always has less priority then reserve.borrowable
     * @param asset The address of the underlying asset of the reserve
     * @param categoryId The eMode categoryId
     * @param borrowable True if the asset should be borrowable in the given eMode category, false otherwise.
     */
    function setAssetBorrowableInEMode(address asset, uint8 categoryId, bool borrowable) external;

    /**
     * @notice Enables/disables an asset to be collateral in a selected eMode.
     * @param asset The address of the underlying asset of the reserve
     * @param categoryId The eMode categoryId
     * @param collateral True if the asset should be collateral in the given eMode category, false otherwise.
     */
    function setAssetCollateralInEMode(address asset, uint8 categoryId, bool collateral) external;

    /**
     * @notice Adds a new efficiency mode (eMode) category or alters a existing one.
     * @param categoryId The id of the category to be configured
     * @param ltv The ltv associated with the category
     * @param liquidationThreshold The liquidation threshold associated with the category
     * @param liquidationBonus The liquidation bonus associated with the category
     * @param label A label identifying the category
     */
    function setEModeCategory(
        uint8 categoryId,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        string calldata label
    ) external;

    /**
     * @notice Drops a reserve entirely.
     * @param asset The address of the reserve to drop
     */
    function dropReserve(address asset) external;

    /**
     * @notice Updates the bridge fee collected by the protocol reserves.
     * @param newBridgeProtocolFee The part of the fee sent to the protocol treasury, expressed in bps
     */
    function updateBridgeProtocolFee(uint256 newBridgeProtocolFee) external;

    /**
     * @notice Updates the total flash loan premium.
     * Total flash loan premium consists of two parts:
     * - A part is sent to aToken holders as extra balance
     * - A part is collected by the protocol reserves
     * @dev Expressed in bps
     * @dev The premium is calculated on the total amount borrowed
     * @param newFlashloanPremiumTotal The total flashloan premium
     */
    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external;

    /**
     * @notice Updates the flash loan premium collected by protocol reserves
     * @dev Expressed in bps
     * @dev The premium to protocol is calculated on the total flashloan premium
     * @param newFlashloanPremiumToProtocol The part of the flashloan premium sent to the protocol treasury
     */
    function updateFlashloanPremiumToProtocol(uint128 newFlashloanPremiumToProtocol) external;

    /**
     * @notice Sets the debt ceiling for an asset.
     * @param newDebtCeiling The new debt ceiling
     */
    function setDebtCeiling(address asset, uint256 newDebtCeiling) external;

    /**
     * @notice Sets siloed borrowing for an asset
     * @param siloed The new siloed borrowing state
     */
    function setSiloedBorrowing(address asset, bool siloed) external;
}
