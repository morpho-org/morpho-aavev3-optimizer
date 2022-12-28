// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

library Errors {
    error MarketNotCreated();
    error AddressIsZero();
    error SupplyIsPaused();
    error BorrowIsPaused();
    error BorrowingNotEnabled();
    error PriceOracleSentinelBorrowDisabled();
    error UnauthorisedBorrow();
    error AmountIsZero();
    error RepayIsPaused();
    error WithdrawIsPaused();
    error PriceOracleSentinelBorrowPaused();
    error WithdrawUnauthorized();
    error LiquidateCollateralIsPaused();
    error LiquidateBorrowIsPaused();
    error UserNotMemberOfMarket();
    error UnauthorisedLiquidate();
}
