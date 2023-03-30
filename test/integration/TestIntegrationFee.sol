// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationFee is IntegrationTest {
    using TestConfigLib for TestConfig;
    using TestMarketLib for TestMarket;
    using PoolLib for IPool;
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function _assertFee(Types.Market memory marketBefore, uint256 morphoBalanceBefore) internal {
        Types.Market memory marketAfter = morpho.market(marketBefore.underlying);

        uint256 p2pBorrow = marketBefore.deltas.borrow.scaledP2PTotal.rayMul(marketBefore.indexes.borrow.p2pIndex)
            .zeroFloorSub(marketBefore.deltas.borrow.scaledDelta.rayMul(marketBefore.indexes.borrow.poolIndex));
        uint256 spread = uint256(marketAfter.indexes.borrow.poolIndex).rayDiv(marketBefore.indexes.borrow.poolIndex)
            - uint256(marketAfter.indexes.supply.poolIndex).rayDiv(marketBefore.indexes.supply.poolIndex);

        uint256 expectedFee = p2pBorrow.rayMul(spread).percentMul(marketBefore.reserveFactor);
        uint256 idleSupplyIncrease = marketAfter.idleSupply - marketBefore.idleSupply;

        assertApproxEqAbs(
            ERC20(marketBefore.underlying).balanceOf(address(morpho)) - morphoBalanceBefore - idleSupplyIncrease,
            expectedFee,
            2,
            "fee != expected"
        );
    }

    function testRepayFeeWithReserveFactorIsZero(uint256 seed, uint256 amount) public {
        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];

        morpho.setReserveFactor(market.underlying, 0);

        amount = _boundSupply(market, amount);
        amount = _promoteBorrow(promoter1, market, amount.percentMul(50_00)); // 100% peer-to-peer.

        _borrowWithoutCollateral(address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }

    function testRepayFeeShouldBeZeroWithDeltaOnly(uint256 seed, uint16 reserveFactor, uint256 amount) public {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));

        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];

        morpho.setReserveFactor(market.underlying, reserveFactor);

        amount = _boundBorrow(market, amount);
        _borrowWithoutCollateral(address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS);

        amount = _increaseBorrowDelta(promoter1, market, amount);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }

    function testRepayFeeWithP2PWithoutDelta(uint256 seed, uint16 reserveFactor, uint256 amount) public {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));

        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];

        morpho.setReserveFactor(market.underlying, reserveFactor);

        amount = _boundBorrow(market, amount);
        amount = _promoteBorrow(promoter1, market, amount.percentMul(50_00)); // 50% peer-to-peer.

        _borrowWithoutCollateral(address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }

    function testRepayFeeWithP2PWithIdleSupply(uint256 seed, uint16 reserveFactor, uint256 amount, uint256 idleSupply)
        public
    {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));

        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];

        morpho.setReserveFactor(market.underlying, reserveFactor);

        amount = _boundBorrow(market, amount);
        amount = _promoteBorrow(promoter1, market, amount.percentMul(50_00)); // 50% peer-to-peer.

        _borrowWithoutCollateral(address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS);
        idleSupply = _increaseIdleSupply(promoter2, market, idleSupply);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }

    function testRepayFeeWithBorrowDeltaAndP2P(
        uint256 seed,
        uint16 reserveFactor,
        uint256 borrowAmount,
        uint256 borrowDeltaAmount
    ) public {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));

        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];

        morpho.setReserveFactor(market.underlying, reserveFactor);

        borrowAmount = bound(borrowAmount, 0, type(uint128).max);
        borrowAmount = _boundBorrow(market, borrowAmount);
        _promoteBorrow(promoter1, market, borrowAmount.percentMul(50_00)); // 50% peer-to-peer.

        _borrowWithoutCollateral(
            address(user), market, borrowAmount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );
        borrowDeltaAmount = _increaseBorrowDelta(user, market, borrowDeltaAmount);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }

    function testRepayFeeWithBorrowDeltaWithP2PWithIdleSupply(
        uint256 seed,
        uint16 reserveFactor,
        uint256 borrowAmount,
        uint256 borrowDeltaAmount,
        uint256 idleSupply
    ) public {
        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        morpho.setReserveFactor(market.underlying, reserveFactor);

        borrowAmount = bound(borrowDeltaAmount, 1, market.liquidity());
        borrowAmount = _boundBorrow(market, borrowAmount);
        _promoteBorrow(promoter1, market, borrowAmount.percentMul(50_00)); // 50% peer-to-peer.

        _borrowWithoutCollateral(
            address(user), market, borrowAmount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        borrowDeltaAmount = _increaseBorrowDelta(user, market, borrowDeltaAmount);
        idleSupply = _increaseIdleSupply(promoter2, market, idleSupply);

        Types.Market memory marketBefore = morpho.market(market.underlying);

        vm.warp(block.timestamp + (365 days));

        uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        user.approve(market.underlying, type(uint256).max);
        user.repay(market.underlying, type(uint256).max);

        _assertFee(marketBefore, balanceBefore);
    }
}
