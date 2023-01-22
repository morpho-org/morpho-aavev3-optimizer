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

abstract contract MorphoSetters is IMorphoSetters, MorphoInternal {
    using MarketLib for Types.Market;

    /// INITIALIZER ///

    function initialize(address newPositionsManager, Types.MaxLoops memory newDefaultMaxLoops) external initializer {
        __Ownable_init_unchained();

        _positionsManager = newPositionsManager;
        _defaultMaxLoops = newDefaultMaxLoops;

        emit Events.DefaultMaxLoopsSet(newDefaultMaxLoops.repay, newDefaultMaxLoops.withdraw);
        emit Events.PositionsManagerSet(newPositionsManager);
    }

    /// GOVERNANCE UTILS ///

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external onlyOwner {
        _createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function claimToTreasury(address[] calldata underlyings, uint256[] calldata amounts) external onlyOwner {
        _claimToTreasury(underlyings, amounts);
    }

    function increaseP2PDeltas(address underlying, uint256 amount) external onlyOwner isMarketCreated(underlying) {
        _increaseP2PDeltas(underlying, amount);
    }

    /// SETTERS ///

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
        _market[underlying].setIsSupplyPaused(underlying, isPaused);
    }

    function setIsSupplyCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsSupplyCollateralPaused(underlying, isPaused);
    }

    function setIsBorrowPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        Types.Market storage market = _market[underlying];
        if (!isPaused && market.isDeprecated()) revert Errors.MarketIsDeprecated();

        market.setIsBorrowPaused(underlying, isPaused);
    }

    function setIsRepayPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsRepayPaused(underlying, isPaused);
    }

    function setIsWithdrawPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].setIsWithdrawPaused(underlying, isPaused);
    }

    function setIsWithdrawCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsWithdrawCollateralPaused(underlying, isPaused);
    }

    function setIsLiquidateCollateralPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsLiquidateCollateralPaused(underlying, isPaused);
    }

    function setIsLiquidateBorrowPaused(address underlying, bool isPaused)
        external
        onlyOwner
        isMarketCreated(underlying)
    {
        _market[underlying].setIsLiquidateBorrowPaused(underlying, isPaused);
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
        _market[underlying].setIsP2PDisabled(underlying, isP2PDisabled);
    }

    function setIsDeprecated(address underlying, bool isDeprecated) external onlyOwner isMarketCreated(underlying) {
        Types.Market storage market = _market[underlying];
        if (!market.isBorrowPaused()) revert Errors.BorrowNotPaused();

        market.setIsDeprecated(underlying, isDeprecated);
    }
}
