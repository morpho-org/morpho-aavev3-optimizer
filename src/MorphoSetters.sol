// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorphoSetters} from "./interfaces/IMorpho.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoSetters is IMorphoSetters, MorphoInternal {
    /// SETTERS ///

    function initialize(address newPositionsManager, Types.MaxLoops memory newDefaultMaxLoops) external initializer {
        __Ownable_init_unchained();

        _positionsManager = newPositionsManager;
        _defaultMaxLoops = newDefaultMaxLoops;
    }

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external onlyOwner {
        _createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function claimToTreasury(address[] calldata underlyings, uint256[] calldata amounts) external onlyOwner {
        _claimToTreasury(underlyings, amounts);
    }

    function increaseP2PDeltas(address underlying, uint256 amount) external onlyOwner isMarketCreated(underlying) {
        _increaseP2PDeltas(underlying, amount);
    }

    function setDefaultMaxLoops(Types.MaxLoops calldata defaultMaxLoops) external onlyOwner {
        _defaultMaxLoops = defaultMaxLoops;
        emit Events.DefaultMaxLoopsSet(defaultMaxLoops.repay, defaultMaxLoops.withdraw);
    }

    function setPositionsManager(address positionsManager) external onlyOwner {
        if (positionsManager == address(0)) revert Errors.AddressIsZero();
        _positionsManager = positionsManager;
        emit Events.PositionsManagerSet(positionsManager);
    }

    function setRewardsManager(address rewardsManager) external onlyOwner {
        _rewardsManager = IRewardsManager(rewardsManager);
        emit Events.RewardsManagerSet(rewardsManager);
    }

    function setTreasuryVault(address treasuryVault) external onlyOwner {
        _treasuryVault = treasuryVault;
        emit Events.TreasuryVaultSet(treasuryVault);
    }

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

    function setIsSupplyPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].pauseStatuses.isSupplyPaused = isPaused;
        emit Events.IsSupplyPausedSet(underlying, isPaused);
    }

    function setIsSupplyCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].pauseStatuses.isSupplyCollateralPaused = isPaused;
        emit Events.IsSupplyCollateralPausedSet(underlying, isPaused);
    }

    function setIsBorrowPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        Types.PauseStatuses storage pauseStatuses = _market[underlying].pauseStatuses;
        if (!isPaused && pauseStatuses.isDeprecated) revert Errors.MarketIsDeprecated();
        pauseStatuses.isBorrowPaused = isPaused;
        emit Events.IsBorrowPausedSet(underlying, isPaused);
    }

    function setIsRepayPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].pauseStatuses.isRepayPaused = isPaused;
        emit Events.IsRepayPausedSet(underlying, isPaused);
    }

    function setIsWithdrawPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].pauseStatuses.isWithdrawPaused = isPaused;
        emit Events.IsWithdrawPausedSet(underlying, isPaused);
    }

    function setIsWithdrawCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].pauseStatuses.isWithdrawCollateralPaused = isPaused;
        emit Events.IsWithdrawCollateralPausedSet(underlying, isPaused);
    }

    function setIsLiquidateCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].pauseStatuses.isLiquidateCollateralPaused = isPaused;
        emit Events.IsLiquidateCollateralPausedSet(underlying, isPaused);
    }

    function setIsLiquidateBorrowPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].pauseStatuses.isLiquidateBorrowPaused = isPaused;
        emit Events.IsLiquidateBorrowPausedSet(underlying, isPaused);
    }

    function setIsPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _setPauseStatus(underlying, isPaused);
    }

    function setIsPausedForAllMarkets(bool isPaused) external onlyOwner {
        uint256 marketsCreatedLength = _marketsCreated.length;
        for (uint256 i; i < marketsCreatedLength; ++i) {
            _setPauseStatus(_marketsCreated[i], isPaused);
        }
    }

    function setIsP2PDisabled(address underlying, bool isP2PDisabled) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].pauseStatuses.isP2PDisabled = isP2PDisabled;
        emit Events.IsP2PDisabledSet(underlying, isP2PDisabled);
    }

    function setIsDeprecated(address underlying, bool isDeprecated) external onlyOwner isMarketCreated(underlying) {
        Types.PauseStatuses storage pauseStatuses = _market[underlying].pauseStatuses;
        if (!pauseStatuses.isBorrowPaused) revert Errors.BorrowNotPaused();
        pauseStatuses.isDeprecated = isDeprecated;
        emit Events.IsDeprecatedSet(underlying, isDeprecated);
    }
}
