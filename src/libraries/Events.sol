// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

library Events {
    event Supplied(
        address indexed from,
        address indexed onBehalf,
        address indexed underlying,
        uint256 amount,
        uint256 scaledOnPool,
        uint256 scaledInP2P
    );

    event CollateralSupplied(
        address indexed from,
        address indexed onBehalf,
        address indexed underlying,
        uint256 amount,
        uint256 scaledBalance
    );

    event Borrowed(
        address indexed borrower,
        address indexed receiver,
        address indexed underlying,
        uint256 amount,
        uint256 scaledOnPool,
        uint256 scaledInP2P
    );

    event Withdrawn(
        address indexed supplier,
        address indexed receiver,
        address indexed underlying,
        uint256 amount,
        uint256 scaledOnPool,
        uint256 scaledInP2P
    );

    event CollateralWithdrawn(
        address indexed supplier,
        address indexed receiver,
        address indexed underlying,
        uint256 amount,
        uint256 scaledBalance
    );

    event Repaid(
        address indexed repayer,
        address indexed onBehalf,
        address indexed underlying,
        uint256 amount,
        uint256 scaledOnPool,
        uint256 scaledInP2P
    );

    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address underlyingBorrowed,
        uint256 amountLiquidated,
        address underlyingCollateral,
        uint256 amountSeized
    );

    event ManagerApproval(address indexed owner, address indexed manager, bool isAllowed);

    event SupplyPositionUpdated(
        address indexed user, address indexed underlying, uint256 scaledOnPool, uint256 scaledInP2P
    );

    event BorrowPositionUpdated(
        address indexed user, address indexed underlying, uint256 scaledOnPool, uint256 scaledInP2P
    );

    event P2PSupplyDeltaUpdated(address indexed underlying, uint256 supplyDelta);

    event P2PBorrowDeltaUpdated(address indexed underlying, uint256 borrowDelta);

    event P2PTotalsUpdated(address indexed underlying, uint256 scaledTotalSupplyP2P, uint256 scaledTotalBorrowP2P);

    event RewardsClaimed(
        address indexed claimer, address indexed user, address indexed rewardToken, uint256 amountClaimed
    );

    event IsSupplyPausedSet(address indexed underlying, bool isPaused);

    event IsSupplyCollateralPausedSet(address indexed underlying, bool isPaused);

    event IsBorrowPausedSet(address indexed underlying, bool isPaused);

    event IsWithdrawPausedSet(address indexed underlying, bool isPaused);

    event IsWithdrawCollateralPausedSet(address indexed underlying, bool isPaused);

    event IsRepayPausedSet(address indexed underlying, bool isPaused);

    event IsLiquidateCollateralPausedSet(address indexed underlying, bool isPaused);

    event IsLiquidateBorrowPausedSet(address indexed underlying, bool isPaused);

    event P2PDeltasIncreased(address indexed underlying, uint256 amount);

    event MarketCreated(address indexed underlying, uint16 reserveFactor, uint16 p2pIndexCursor);

    event DefaultMaxLoopsSet(uint64 supply, uint64 borrow, uint64 repay, uint64 withdraw);

    event PositionsManagerSet(address indexed positionsManager);

    event RewardsManagerSet(address indexed rewardsManager);

    event ReserveFactorSet(address indexed underlying, uint16 reserveFactor);

    event P2PIndexCursorSet(address indexed underlying, uint16 p2pIndexCursor);

    event IsP2PDisabledSet(address indexed underlying, bool isP2PDisabled);

    event IsDeprecatedSet(address indexed underlying, bool isDeprecated);

    event IndexesUpdated(
        address indexed underlying,
        uint256 p2pSupplyIndex,
        uint256 p2pBorrowIndex,
        uint256 poolSupplyIndex,
        uint256 poolBorrowIndex
    );
}
