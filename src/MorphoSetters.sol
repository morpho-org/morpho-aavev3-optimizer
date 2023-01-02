// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPoolAddressesProvider, IPool} from "./interfaces/aave/IPool.sol";

import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";

import {DataTypes} from "./libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {IPoolAddressesProvider, IPool} from "./interfaces/aave/IPool.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MorphoSetters is MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using SafeTransferLib for ERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// SETTERS ///

    function initialize(
        address newEntryPositionsManager,
        address newExitPositionsManager,
        address newAddressesProvider,
        Types.MaxLoops memory newDefaultMaxLoops,
        uint256 newMaxSortedUsers
    ) external initializer {
        if (newMaxSortedUsers == 0) revert Errors.MaxSortedUsersCannotBeZero();
        _transferOwnership(msg.sender);
        _entryPositionsManager = newEntryPositionsManager;
        _exitPositionsManager = newExitPositionsManager;
        _addressesProvider = IPoolAddressesProvider(newAddressesProvider);
        _pool = IPool(_addressesProvider.getPool());

        _defaultMaxLoops = newDefaultMaxLoops;
        _maxSortedUsers = newMaxSortedUsers;
    }

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external onlyOwner {
        if (underlying == address(0)) revert Errors.AddressIsZero();
        if (p2pIndexCursor > PercentageMath.PERCENTAGE_FACTOR || reserveFactor > PercentageMath.PERCENTAGE_FACTOR) {
            revert Errors.ExceedsMaxBasisPoints();
        }

        if (!_pool.getConfiguration(underlying).getActive()) revert Errors.MarketIsNotListedOnAave();

        DataTypes.ReserveData memory reserveData = _pool.getReserveData(underlying);

        Types.Market storage market = _market[underlying];

        if (market.isCreated()) revert Errors.MarketAlreadyCreated();

        Types.Indexes256 memory indexes;
        indexes.p2pSupplyIndex = WadRayMath.RAY;
        indexes.p2pBorrowIndex = WadRayMath.RAY;
        // TODO: Fix for IB tokens
        indexes.poolSupplyIndex = _pool.getReserveNormalizedIncome(underlying);
        indexes.poolBorrowIndex = _pool.getReserveNormalizedVariableDebt(underlying);

        market.setIndexes(indexes);
        market.lastUpdateTimestamp = uint32(block.timestamp);

        market.underlying = underlying;
        market.aToken = reserveData.aTokenAddress;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(underlying);

        ERC20(underlying).safeApprove(address(_pool), type(uint256).max);

        emit Events.MarketCreated(underlying, reserveFactor, p2pIndexCursor);
    }

    function setMaxSortedUsers(uint256 newMaxSortedUsers) external onlyOwner {
        if (newMaxSortedUsers == 0) revert Errors.MaxSortedUsersCannotBeZero();
        _maxSortedUsers = newMaxSortedUsers;
        emit Events.MaxSortedUsersSet(newMaxSortedUsers);
    }

    function setDefaultMaxLoops(Types.MaxLoops memory defaultMaxLoops) external onlyOwner {
        _defaultMaxLoops = defaultMaxLoops;
        emit Events.DefaultMaxLoopsSet(
            _defaultMaxLoops.supply, _defaultMaxLoops.borrow, _defaultMaxLoops.repay, _defaultMaxLoops.withdraw
            );
    }

    function setEntryPositionsManager(address entryPositionsManager) external onlyOwner {
        if (entryPositionsManager == address(0)) revert Errors.AddressIsZero();
        _entryPositionsManager = entryPositionsManager;
        emit Events.EntryPositionsManagerSet(entryPositionsManager);
    }

    function setExitPositionsManager(address exitPositionsManager) external onlyOwner {
        if (exitPositionsManager == address(0)) revert Errors.AddressIsZero();
        _exitPositionsManager = exitPositionsManager;
        emit Events.ExitPositionsManagerSet(_exitPositionsManager);
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

    function setIsBorrowPaused(address underlying, bool isPaused) external onlyOwner isMarketCreated(underlying) {
        _market[underlying].pauseStatuses.isBorrowPaused = isPaused;
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
        _market[underlying].pauseStatuses.isDeprecated = isDeprecated;
        emit Events.IsDeprecatedSet(underlying, isDeprecated);
    }
}
