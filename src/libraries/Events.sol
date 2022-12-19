// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Events {
    event PositionUpdated(
        bool borrow, address indexed user, address indexed poolToken, uint256 balanceOnPool, uint256 balanceInP2P
    );

    event IsSupplyPausedSet(address indexed poolToken, bool isPaused);

    event IsBorrowPausedSet(address indexed poolToken, bool isPaused);

    event IsWithdrawPausedSet(address indexed poolToken, bool isPaused);

    event IsRepayPausedSet(address indexed poolToken, bool isPaused);

    event IsLiquidateCollateralPausedSet(address indexed poolToken, bool isPaused);

    event IsLiquidateBorrowPausedSet(address indexed poolToken, bool isPaused);
}
