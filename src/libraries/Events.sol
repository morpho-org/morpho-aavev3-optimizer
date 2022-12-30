// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

library Events {
    event Supplied(
        address indexed from,
        address indexed onBehalf,
        address indexed underlying,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event CollateralSupplied(
        address indexed from, address indexed onBehalf, address indexed underlying, uint256 amount, uint256 balance
    );

    event Borrowed(
        address indexed borrower,
        address indexed underlying,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event Withdrawn(
        address indexed supplier,
        address indexed receiver,
        address indexed underlying,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event CollateralWithdrawn(
        address indexed supplier, address indexed receiver, address indexed underlying, uint256 amount, uint256 balance
    );

    event Repaid(
        address indexed repayer,
        address indexed onBehalf,
        address indexed underlying,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address underlyingBorrowed,
        uint256 amountLiquidated,
        address underlyingCollateral,
        uint256 amountSeized
    );

    event PositionUpdated(
        bool borrow, address indexed user, address indexed underlying, uint256 balanceOnPool, uint256 balanceInP2P
    );

    event IsSupplyPausedSet(address indexed underlying, bool isPaused);

    event IsBorrowPausedSet(address indexed underlying, bool isPaused);

    event IsWithdrawPausedSet(address indexed underlying, bool isPaused);

    event IsRepayPausedSet(address indexed underlying, bool isPaused);

    event IsLiquidateCollateralPausedSet(address indexed underlying, bool isPaused);

    event IsLiquidateBorrowPausedSet(address indexed underlying, bool isPaused);

    event P2PBorrowDeltaUpdated(address indexed underlying, uint256 borrowDelta);

    event P2PAmountsUpdated(address indexed underlying, uint256 p2pSupplyAmount, uint256 p2pBorrowAmount);

    event P2PSupplyDeltaUpdated(address indexed underlying, uint256 p2pSupplyDelta);

    event MarketCreated(address indexed underlying, uint16 reserveFactor, uint16 p2pIndexCursor);

    event MaxSortedUsersSet(uint256 maxSortedUsers);

    event DefaultMaxLoopsSet(uint64 supply, uint64 borrow, uint64 repay, uint64 withdraw);

    event EntryPositionsManagerSet(address entryPositionsManager);

    event ExitPositionsManagerSet(address exitPositionsManager);

    event ReserveFactorSet(address indexed underlying, uint16 reserveFactor);

    event P2PIndexCursorSet(address indexed underlying, uint16 p2pIndexCursor);

    event IsP2PDisabledSet(address indexed underlying, bool isP2PDisabled);

    event IsDeprecatedSet(address indexed underlying, bool isDeprecated);
}
