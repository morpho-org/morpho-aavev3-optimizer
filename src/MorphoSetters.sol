// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoSetters} from "./interfaces/IMorpho.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {MarketLib} from "./libraries/MarketLib.sol";

import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

/// @title MorphoSetters
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Abstract contract exposing all setters and governance-related functions.
abstract contract MorphoSetters is IMorphoSetters, MorphoInternal {
    using MarketLib for Types.Market;

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param underlying The address of the underlying market.
    modifier isMarketCreated(address underlying) {
        if (!_market[underlying].isCreated()) revert Errors.MarketNotCreated();
        _;
    }

    /// INITIALIZER ///

    /// @notice Initializes the contract.
    /// @param newPositionsManager The address of the `_positionsManager` to set.
    /// @param newDefaultMaxIterations The `_defaultMaxIterations` to set.
    function initialize(address newPositionsManager, Types.MaxIterations memory newDefaultMaxIterations)
        external
        initializer
    {
        __Ownable_init_unchained();

        _positionsManager = newPositionsManager;
        _defaultMaxIterations = newDefaultMaxIterations;

        emit Events.DefaultMaxIterationsSet(newDefaultMaxIterations.repay, newDefaultMaxIterations.withdraw);
        emit Events.PositionsManagerSet(newPositionsManager);
    }

    /// GOVERNANCE UTILS ///

    /// @notice Creates a new market for the `underlying` token with a given `reserveFactor` (in bps) and a given `p2pIndexCursor` (in bps).
    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external onlyOwner {
        _createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    /// @notice Claims the fee for the `underlyings` and send it to the `_treasuryVault`.
    function claimToTreasury(address[] calldata underlyings, uint256[] calldata amounts) external onlyOwner {
        _claimToTreasury(underlyings, amounts);
    }

    /// @notice Increases the peer-to-peer delta of `amount` on the `underlying` market.
    function increaseP2PDeltas(address underlying, uint256 amount) external onlyOwner isMarketCreated(underlying) {
        _increaseP2PDeltas(underlying, amount);
    }

    /// SETTERS ///

    /// @notice Sets `_defaultMaxIterations` to `defaultMaxIterations`.
    function setDefaultMaxIterations(Types.MaxIterations calldata defaultMaxIterations) external onlyOwner {
        _defaultMaxIterations = defaultMaxIterations;
        emit Events.DefaultMaxIterationsSet(defaultMaxIterations.repay, defaultMaxIterations.withdraw);
    }

    /// @notice Sets `_positionsManager` to `positionsManager`.
    function setPositionsManager(address positionsManager) external onlyOwner {
        if (positionsManager == address(0)) revert Errors.AddressIsZero();
        _positionsManager = positionsManager;
        emit Events.PositionsManagerSet(positionsManager);
    }

    /// @notice Sets `_rewardsManager` to `rewardsManager`.
    function setRewardsManager(address rewardsManager) external onlyOwner {
        _rewardsManager = IRewardsManager(rewardsManager);
        emit Events.RewardsManagerSet(rewardsManager);
    }

    /// @notice Sets `_treasuryVault` to `treasuryVault`.
    function setTreasuryVault(address treasuryVault) external onlyOwner {
        _treasuryVault = treasuryVault;
        emit Events.TreasuryVaultSet(treasuryVault);
    }

    /// @notice Sets the `underlying`'s reserve factor to newReserveFactor (in bps).
    function setReserveFactor(address underlying, uint16 newReserveFactor)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        if (newReserveFactor > PercentageMath.PERCENTAGE_FACTOR) revert Errors.ExceedsMaxBasisPoints();
        _updateIndexes(underlying);

        _market[underlying].reserveFactor = newReserveFactor;
        emit Events.ReserveFactorSet(underlying, newReserveFactor);
    }

    /// @notice Sets the `underlying`'s peer-to-peer index cursor to `p2pIndexCursor` (in bps).
    function setP2PIndexCursor(address underlying, uint16 p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        if (p2pIndexCursor > PercentageMath.PERCENTAGE_FACTOR) revert Errors.ExceedsMaxBasisPoints();
        _updateIndexes(underlying);

        _market[underlying].p2pIndexCursor = p2pIndexCursor;
        emit Events.P2PIndexCursorSet(underlying, p2pIndexCursor);
    }

    /// @notice Sets the supply pause status to `isPaused` on the `underlying` market.
    function setIsSupplyPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsSupplyPaused(underlying, isPaused);
    }

    /// @notice Sets the supply collateral pause status to `isPaused` on the `underlying` market.
    function setIsSupplyCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsSupplyCollateralPaused(underlying, isPaused);
    }

    /// @notice Sets the borrow pause status to `isPaused` on the `underlying` market.
    function setIsBorrowPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        Types.Market storage market = _market[underlying];
        if (!isPaused && market.isDeprecated()) revert Errors.MarketIsDeprecated();

        market.setIsBorrowPaused(underlying, isPaused);
    }

    /// @notice Sets the repay pause status to `isPaused` on the `underlying` market.
    function setIsRepayPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsRepayPaused(underlying, isPaused);
    }

    /// @notice Sets the withdraw pause status to `isPaused` on the `underlying` market.
    function setIsWithdrawPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsWithdrawPaused(underlying, isPaused);
    }

    /// @notice Sets the withdraw collateral pause status to `isPaused` on the `underlying` market.
    function setIsWithdrawCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsWithdrawCollateralPaused(underlying, isPaused);
    }

    /// @notice Sets the liquidate collateral pause status to `isPaused` on the `underlying` market.
    function setIsLiquidateCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsLiquidateCollateralPaused(underlying, isPaused);
    }

    /// @notice Sets the liquidate borrow pause status to `isPaused` on the `underlying` market.
    function setIsLiquidateBorrowPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsLiquidateBorrowPaused(underlying, isPaused);
    }

    /// @notice Sets globally the pause status to `isPaused` on the `underlying` market.
    function setIsPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _setPauseStatus(underlying, isPaused);
    }

    /// @notice Sets the global pause status to `isPaused` on all markets.
    function setIsPausedForAllMarkets(bool isPaused) external onlyOwner {
        uint256 marketsCreatedLength = _marketsCreated.length;
        for (uint256 i; i < marketsCreatedLength; ++i) {
            _setPauseStatus(_marketsCreated[i], isPaused);
        }
    }

    /// @notice Sets the peer-to-peer disable status to `isP2PDisabled` on the `underlying` market.
    function setIsP2PDisabled(address underlying, bool isP2PDisabled) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsP2PDisabled(underlying, isP2PDisabled);
    }

    /// @notice Sets the deprecation status to `isDeprecated` on the `underlying` market.
    function setIsDeprecated(address underlying, bool isDeprecated) external onlyOwner isMarketCreated(underlying) {
        Types.Market storage market = _market[underlying];
        if (!market.isBorrowPaused()) revert Errors.BorrowNotPaused();

        market.setIsDeprecated(underlying, isDeprecated);
    }
}
