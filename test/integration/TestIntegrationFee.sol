// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationFee is IntegrationTest {
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function testRepayFeeWithReserveFactorIsZero(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];
            morpho.setReserveFactor(market.underlying, 0);

            amount = _boundSupply(market, amount);
            amount = _promoteBorrow(promoter1, market, amount.percentMul(50_00)); // 100% peer-to-peer.

            _borrowWithoutCollateral(
                address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));
            vm.warp(block.timestamp + (365 days));

            user.approve(market.underlying, type(uint256).max);
            user.repay(market.underlying, type(uint256).max);

            assertEq(balanceBefore, ERC20(market.underlying).balanceOf(address(morpho)), "Fee collected != 0");
        }
    }

    function testRepayFeeShouldBeZeroWithDeltaOnly(uint16 reserveFactor, uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];
            reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
            morpho.setReserveFactor(market.underlying, reserveFactor);

            amount = _boundBorrow(market, amount);
            _borrowWithoutCollateral(
                address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );

            amount = _increaseBorrowDelta(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(address(morpho));
            vm.warp(block.timestamp + (365 days));

            user.approve(market.underlying, type(uint256).max);
            user.repay(market.underlying, type(uint256).max);

            assertApproxEqAbs(
                ERC20(market.underlying).balanceOf(address(morpho)), balanceBefore, 1, "Fee collected != 0"
            );
        }
    }

    function testRepayFeeWithP2PWithoutDelta(uint16 reserveFactor, uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage testMarket = testMarkets[borrowableUnderlyings[marketIndex]];
            reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
            morpho.setReserveFactor(testMarket.underlying, reserveFactor);

            amount = _boundBorrow(testMarket, amount);
            amount = _promoteBorrow(promoter1, testMarket, amount.percentMul(50_00)); // 100% peer-to-peer.

            _borrowWithoutCollateral(
                address(user), testMarket, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );

            Types.Indexes256 memory lastIndexes = morpho.updatedIndexes(testMarket.underlying);
            Types.Market memory market = morpho.market(testMarket.underlying);
            Types.Deltas memory deltas = market.deltas;
            uint256 lastBorrowP2PBalance = deltas.borrow.scaledP2PTotal.rayMul(lastIndexes.borrow.p2pIndex)
                - deltas.borrow.scaledDelta.rayMul(lastIndexes.borrow.poolIndex);

            vm.warp(block.timestamp + (365 days));

            Types.Indexes256 memory indexes = morpho.updatedIndexes(testMarket.underlying);
            uint256 poolBorrowGrowth = indexes.borrow.poolIndex.rayDiv(lastIndexes.borrow.poolIndex);
            uint256 poolSupplyGrowth = indexes.supply.poolIndex.rayDiv(lastIndexes.supply.poolIndex);

            uint256 expectedFeeCollected =
                lastBorrowP2PBalance.rayMul(poolBorrowGrowth.zeroFloorSub(poolSupplyGrowth)).percentMul(reserveFactor);

            uint256 balanceBefore = ERC20(testMarket.underlying).balanceOf(address(morpho));

            user.approve(market.underlying, type(uint256).max);

            user.repay(market.underlying, type(uint256).max);

            assertApproxEqAbs(
                ERC20(testMarket.underlying).balanceOf(address(morpho)),
                balanceBefore + expectedFeeCollected,
                2,
                "Right amount of fees collected"
            );
        }
    }

    function testRepayFeeWithBorrowDeltaAndP2P(uint16 reserveFactor, uint256 borrowAmount, uint256 borrowDeltaAmount)
        public
    {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage testMarket = testMarkets[borrowableUnderlyings[marketIndex]];
            reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
            morpho.setReserveFactor(testMarket.underlying, reserveFactor);

            borrowAmount = bound(borrowAmount, 0, type(uint128).max);
            borrowAmount = _boundBorrow(testMarket, borrowAmount);
            _promoteBorrow(promoter1, testMarket, borrowAmount.percentMul(50_00));

            _borrowWithoutCollateral(
                address(user), testMarket, borrowAmount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );
            borrowDeltaAmount = _increaseBorrowDelta(user, testMarket, borrowDeltaAmount);

            Types.Indexes256 memory lastIndexes = morpho.updatedIndexes(testMarket.underlying);
            Types.Market memory market = morpho.market(testMarket.underlying);
            Types.Deltas memory deltas = market.deltas;
            uint256 lastBorrowP2PBalance = deltas.borrow.scaledP2PTotal.rayMul(lastIndexes.borrow.p2pIndex)
                - deltas.borrow.scaledDelta.rayMul(lastIndexes.borrow.poolIndex);

            vm.warp(block.timestamp + (365 days));

            Types.Indexes256 memory indexes = morpho.updatedIndexes(testMarket.underlying);
            uint256 poolBorrowGrowth = indexes.borrow.poolIndex.rayDiv(lastIndexes.borrow.poolIndex);
            uint256 poolSupplyGrowth = indexes.supply.poolIndex.rayDiv(lastIndexes.supply.poolIndex);

            uint256 expectedFeeCollected =
                lastBorrowP2PBalance.rayMul(poolBorrowGrowth.zeroFloorSub(poolSupplyGrowth)).percentMul(reserveFactor);

            uint256 balanceBefore = ERC20(testMarket.underlying).balanceOf(address(morpho));

            user.approve(testMarket.underlying, type(uint256).max);
            user.repay(testMarket.underlying, type(uint256).max);

            assertApproxEqAbs(
                ERC20(testMarket.underlying).balanceOf(address(morpho)),
                balanceBefore + expectedFeeCollected,
                3,
                "Wrong amount of fees"
            );
        }
    }
}
