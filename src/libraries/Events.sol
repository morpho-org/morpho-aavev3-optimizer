// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Events {
    event Supplied(
        address indexed _from,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    event Borrowed(
        address indexed _borrower,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    event Withdrawn(
        address indexed _supplier,
        address indexed _receiver,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    event Repaid(
        address indexed _repayer,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    event Liquidated(
        address indexed _liquidator,
        address indexed _borrower,
        address _poolTokenBorrowed,
        uint256 _amountLiquidated,
        address _poolTokenCollateral,
        uint256 _amountSeized
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
}
