// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/// @title Errors
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing errors used in Morpho.
library Errors {
    /// @notice Thrown when interacting with a market that is not created.
    error MarketNotCreated();

    /// @notice Thrown when creating a market that is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when creating a market that is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the address used is the zero address.
    error AddressIsZero();

    /// @notice Thrown when the amount used is zero.
    error AmountIsZero();

    /// @notice Thrown when the manager is not approved by the delegator.
    error PermissionDenied();

    /// @notice Thrown when supply is paused.
    error SupplyIsPaused();

    /// @notice Thrown when supply collateral is paused.
    error SupplyCollateralIsPaused();

    /// @notice Thrown when borrow is paused.
    error BorrowIsPaused();

    /// @notice Thrown when repay is paused.
    error RepayIsPaused();

    /// @notice Thrown when withdraw is paused.
    error WithdrawIsPaused();

    /// @notice Thrown when withdraw collateral is paused.
    error WithdrawCollateralIsPaused();

    /// @notice Thrown when liquidate collateral is paused.
    error LiquidateCollateralIsPaused();

    /// @notice Thrown when liquidate borrow is paused.
    error LiquidateBorrowIsPaused();

    /// @notice Thrown when claim rewards is paused.
    error ClaimRewardsPaused();

    /// @notice Thrown when unpausing the borrow of a market that is deprecated.
    error MarketIsDeprecated();

    /// @notice Thrown when deprecating a market that is not paused.
    error BorrowNotPaused();

    /// @notice Thrown when the market is not enabled on Aave.
    error BorrowNotEnabled();

    /// @notice Thrown when the oracle sentinel is set but the borrow is not enabled.
    error SentinelBorrowNotEnabled();

    /// @notice Thrown when borrowing an asset that is not in Morpho's e-mode category.
    error InconsistentEMode();

    /// @notice Thrown when a borrow would leave the user undercollateralized.
    error UnauthorizedBorrow();

    /// @notice Thrown when a withdraw would leave the user undercollateralized.
    error UnauthorizedWithdraw();

    /// @notice Thrown when the liquidatation is not authorized because of a collateralization ratio too high.
    error UnauthorizedLiquidate();

    /// @notice Thrown when the oracle sentinel is set but the liquidation is not enabled.
    error SentinelLiquidateNotEnabled();

    /// @notice Thrown when setting a market as collateral on Morpho while it is not a collateral on Aave.
    error AssetNotCollateral();

    /// @notice Thrown when unsetting a market as collateral on Aave while it is a collateral on Morpho.
    error AssetIsCollateral();

    /// @notice Thrown when the value exceeds the maximum basis points value (100% = 10000).
    error ExceedsMaxBasisPoints();

    /// @notice Thrown when the s part of the ECDSA signature is invalid.
    error InvalidValueS();

    /// @notice Thrown when the v part of the ECDSA signature is invalid.
    error InvalidValueV();

    /// @notice Thrown when the signatory of the ECDSA signature is invalid.
    error InvalidSignatory();

    /// @notice Thrown when the nonce is invalid.
    error InvalidNonce();

    /// @notice Thrown when the signature is expired
    error SignatureExpired();

    /// @notice Thrown when the borrow cap on Aave is exceeded.
    error ExceedsBorrowCap();
}
