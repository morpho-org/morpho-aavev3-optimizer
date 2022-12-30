// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

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

import {MorphoInternal} from "./MorphoInternal.sol";
import {IPoolAddressesProvider, IPool} from "./interfaces/aave/IPool.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

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

    function createMarket(address underlyingToken, uint16 reserveFactor, uint16 p2pIndexCursor) external onlyOwner {
        if (underlyingToken == address(0)) revert Errors.AddressIsZero();
        if (p2pIndexCursor > PercentageMath.PERCENTAGE_FACTOR || reserveFactor > PercentageMath.PERCENTAGE_FACTOR) {
            revert Errors.ExceedsMaxBasisPoints();
        }

        if (!_pool.getConfiguration(underlyingToken).getActive()) revert Errors.MarketIsNotListedOnAave();

        DataTypes.ReserveData memory reserveData = _pool.getReserveData(underlyingToken);

        address poolToken = reserveData.aTokenAddress;
        Types.Market storage market = _market[poolToken];

        if (market.isCreated()) revert Errors.MarketAlreadyCreated();

        Types.Indexes256 memory indexes;
        indexes.p2pSupplyIndex = WadRayMath.RAY;
        indexes.p2pBorrowIndex = WadRayMath.RAY;
        // TODO: Fix for IB tokens
        indexes.poolSupplyIndex = _pool.getReserveNormalizedIncome(underlyingToken);
        indexes.poolBorrowIndex = _pool.getReserveNormalizedVariableDebt(underlyingToken);

        market.setIndexes(indexes);
        market.lastUpdateTimestamp = uint32(block.timestamp);

        market.underlying = underlyingToken;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(poolToken);

        ERC20(underlyingToken).safeApprove(address(_pool), type(uint256).max);

        emit Events.MarketCreated(poolToken, reserveFactor, p2pIndexCursor);
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

    function setReserveFactor(address poolToken, uint16 newReserveFactor)
        external
        onlyOwner
        isMarketCreated(poolToken)
    {
        if (newReserveFactor > PercentageMath.PERCENTAGE_FACTOR) revert Errors.ExceedsMaxBasisPoints();
        _updateIndexes(poolToken);

        _market[poolToken].reserveFactor = newReserveFactor;
        emit Events.ReserveFactorSet(poolToken, newReserveFactor);
    }

    function setP2PIndexCursor(address poolToken, uint16 p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(poolToken)
    {
        if (p2pIndexCursor > PercentageMath.PERCENTAGE_FACTOR) revert Errors.ExceedsMaxBasisPoints();
        _updateIndexes(poolToken);

        _market[poolToken].p2pIndexCursor = p2pIndexCursor;
        emit Events.P2PIndexCursorSet(poolToken, p2pIndexCursor);
    }

    function setIsSupplyPaused(address poolToken, bool isPaused) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isSupplyPaused = isPaused;
        emit Events.IsSupplyPausedSet(poolToken, isPaused);
    }

    function setIsBorrowPaused(address poolToken, bool isPaused) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isBorrowPaused = isPaused;
        emit Events.IsBorrowPausedSet(poolToken, isPaused);
    }

    function setIsRepayPaused(address poolToken, bool isPaused) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isRepayPaused = isPaused;
        emit Events.IsRepayPausedSet(poolToken, isPaused);
    }

    function setIsWithdrawPaused(address poolToken, bool isPaused) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isWithdrawPaused = isPaused;
        emit Events.IsWithdrawPausedSet(poolToken, isPaused);
    }

    function setIsLiquidateCollateralPaused(address poolToken, bool isPaused)
        external
        onlyOwner
        isMarketCreated(poolToken)
    {
        _market[poolToken].pauseStatuses.isLiquidateCollateralPaused = isPaused;
        emit Events.IsLiquidateCollateralPausedSet(poolToken, isPaused);
    }

    function setIsLiquidateBorrowPaused(address poolToken, bool isPaused)
        external
        onlyOwner
        isMarketCreated(poolToken)
    {
        _market[poolToken].pauseStatuses.isLiquidateBorrowPaused = isPaused;
        emit Events.IsLiquidateBorrowPausedSet(poolToken, isPaused);
    }

    function setIsPaused(address poolToken, bool isPaused) external onlyOwner isMarketCreated(poolToken) {
        _setPauseStatus(poolToken, isPaused);
    }

    function setIsPausedForAllMarkets(bool isPaused) external onlyOwner {
        uint256 marketsCreatedLength = _marketsCreated.length;
        for (uint256 i; i < marketsCreatedLength; ++i) {
            _setPauseStatus(_marketsCreated[i], isPaused);
        }
    }

    function setIsP2PDisabled(address poolToken, bool isP2PDisabled) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isP2PDisabled = isP2PDisabled;
        emit Events.IsP2PDisabledSet(poolToken, isP2PDisabled);
    }

    function setIsDeprecated(address poolToken, bool isDeprecated) external onlyOwner isMarketCreated(poolToken) {
        _market[poolToken].pauseStatuses.isDeprecated = isDeprecated;
        emit Events.IsDeprecatedSet(poolToken, isDeprecated);
    }
}
