// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/// @title Errors
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing errors used in Morpho.
library Errors {
    /// @notice Thrown when interacting with a market not created.
    error MarketNotCreated();

    /// @notice Thrown when trying to create a market already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when trying to create a market that is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the address used is the zero address.
    error AddressIsZero();

    /// @notice Thrown when the amount used is zero.
    error AmountIsZero();

    /// @notice Thrown when the manager has no approval upon the delegator.
    error PermissionDenied();

    /// @notice Thrown when the supply is paused.
    error SupplyIsPaused();

    /// @notice Thrown when the supply collateral is paused.
    error SupplyCollateralIsPaused();

    /// @notice Thrown when the borrow is paused.
    error BorrowIsPaused();

    /// @notice Thrown when the repay is paused.
    error RepayIsPaused();

    /// @notice Thrown when the withdraw is paused.
    error WithdrawIsPaused();

    /// @notice Thrown when the withdraw collateral is paused.
    error WithdrawCollateralIsPaused();

    /// @notice Thrown when the liquidate collateral is paused.
    error LiquidateCollateralIsPaused();

    /// @notice Thrown when the liquidate borrow is paused.
    error LiquidateBorrowIsPaused();

    /// @notice Thrown when the claim rewards is paused.
    error ClaimRewardsPaused();

    /// @notice Thrown when the market is deprecated while trying to unpause the borrow.
    error MarketIsDeprecated();

    /// @notice Thrown when the market is not paused while trying to deprecate it.
    error BorrowNotPaused();

    /// @notice Thrown when the market is not enabled on Aave.
    error BorrowNotEnabled();

    /// @notice Thrown when the oracle sentinel is enabled but the borrow is not.
    error SentinelBorrowNotEnabled();

    /// @notice Thrown when borrowing an asset in an e-mode not consistent with Morpho.
    error InconsistentEMode();

    /// @notice Thrown when the borrow is not authorized because of a collateralization ratio too low.
    error UnauthorizedBorrow();

    /// @notice Thrown when the withdraw is not authorized because of a collateralization ratio too low.
    error UnauthorizedWithdraw();

    /// @notice Thrown when the liquidatation is not authorized because of a collateralization ratio too high.
    error UnauthorizedLiquidate();

    /// @notice Thrown when the oracle sentinel is enabled but the liquidation is not.
    error SentinelLiquidateNotEnabled();

    /// @notice Thrown when the asset is not a collateral on Aave while trying to set it as collateral on Morpho.
    error AssetNotCollateral();

    /// @notice Thrown when the asset is a collateral on Morpho while trying to unset it as collateral on Aave.
    error AssetIsCollateral();

    /// @notice Thrown when the value exceeds the maximum basis points value (100% = 10000).
    error ExceedsMaxBasisPoints();

    /// @notice Thrown when the s part of the ECDSA signature is invalid.
    error InvalidValueS();

    /// @notice Thrown when the v part of the ECDSA signature is invalid.
    error InvalidValueV();

    /// @notice Thrown when the signatory of the ECDSA signature is invalid.
    error InvalidSignatory();

    /// @notice Trown when the nonce is invalid.
    error InvalidNonce();

    /// @notice Thrown when the signature is expired
    error SignatureExpired();

    /// @notice Thrown when the borrow cap on Aave is exceeded.
    error ExceedsBorrowCap();
}
