// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Events {
    event Supplied(
        address indexed from,
        address indexed onBehalf,
        address indexed poolToken,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event CollateralSupplied(
        address indexed from, address indexed onBehalf, address indexed poolToken, uint256 amount, uint256 balance
    );

    event Borrowed(
        address indexed borrower, address indexed poolToken, uint256 amount, uint256 balanceOnPool, uint256 balanceInP2P
    );

    event Withdrawn(
        address indexed supplier,
        address indexed receiver,
        address indexed poolToken,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event CollateralWithdrawn(
        address indexed supplier, address indexed receiver, address indexed poolToken, uint256 amount, uint256 balance
    );

    event Repaid(
        address indexed repayer,
        address indexed onBehalf,
        address indexed poolToken,
        uint256 amount,
        uint256 balanceOnPool,
        uint256 balanceInP2P
    );

    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address poolTokenBorrowed,
        uint256 amountLiquidated,
        address poolTokenCollateral,
        uint256 amountSeized
    );

    event PositionUpdated(
        bool borrow, address indexed user, address indexed poolToken, uint256 balanceOnPool, uint256 balanceInP2P
    );

    event IsSupplyPausedSet(address indexed poolToken, bool isPaused);

    event IsBorrowPausedSet(address indexed poolToken, bool isPaused);

    event IsWithdrawPausedSet(address indexed poolToken, bool isPaused);

    event IsRepayPausedSet(address indexed poolToken, bool isPaused);

    event IsLiquidateCollateralPausedSet(address indexed poolToken, bool isPaused);

    event IsLiquidateBorrowPausedSet(address indexed poolToken, bool isPaused);

    event P2PBorrowDeltaUpdated(address indexed poolToken, uint256 borrowDelta);

    event P2PAmountsUpdated(address indexed poolToken, uint256 p2pSupplyAmount, uint256 p2pBorrowAmount);

    event P2PSupplyDeltaUpdated(address indexed poolToken, uint256 p2pSupplyDelta);

    event MarketCreated(address indexed poolToken, uint16 reserveFactor, uint16 p2pIndexCursor);

    event MaxSortedUsersSet(uint256 maxSortedUsers);

    event DefaultMaxLoopsForMatchingSet(uint64 supply, uint64 borrow, uint64 repay, uint64 withdraw);

    event EntryPositionsManagerSet(address entryPositionsManager);

    event ExitPositionsManagerSet(address exitPositionsManager);

    event ReserveFactorSet(address indexed poolToken, uint16 reserveFactor);

    event P2PIndexCursorSet(address indexed poolToken, uint16 p2pIndexCursor);

    event IsP2PDisabledSet(address indexed poolToken, bool isP2PDisabled);

    event IsDeprecatedSet(address indexed poolToken, bool isDeprecated);
}
