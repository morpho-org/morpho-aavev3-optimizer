// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationFee is IntegrationTest {
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using Math for uint256;
    using WadRayMath for uint256;

    function testRepayFeeWithReserveFactorIsZero(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();
            address underlying = borrowableUnderlyings[marketIndex];
            morpho.setReserveFactor(underlying, 0);
            TestMarket storage market = testMarkets[underlying];

            amount = _boundSupply(market, amount);
            amount = _promoteSupply(promoter1, market, amount); // 100% peer-to-peer.

            user.approve(market.underlying, amount);
            user.supply(market.underlying, amount);

            uint256 beforeBalance = ERC20(underlying).balanceOf(address(morpho));
            vm.warp(block.timestamp + (365 days));

            promoter1.approve(market.underlying, 2 * amount);
            promoter1.repay(market.underlying, 2 * amount);

            assertEq(beforeBalance, ERC20(underlying).balanceOf(address(morpho)), "Fee collected");
        }
    }

    function testRepayFeeShouldBeZeroWithBorrowDelta(uint16 reserveFactor, uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];
            reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
            morpho.setReserveFactor(market.underlying, reserveFactor);

            amount = _boundBorrow(market, amount);
            _borrowWithoutCollateral(
                address(user), market, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );

            amount = _increaseBorrowDelta(promoter1, market, amount / 2);

            uint256 beforeBalance = ERC20(market.underlying).balanceOf(address(morpho));
            vm.warp(block.timestamp + (365 days));

            user.approve(market.underlying, 2 * amount);
            user.repay(market.underlying, 2 * amount);

            assertEq(beforeBalance, ERC20(market.underlying).balanceOf(address(morpho)), "Fee collected");
        }
    }

    function testRepayFeeWithP2POnly(uint16 reserveFactor, uint256 amount) public {
        for (uint256 marketIndex; marketIndex < 1; ++marketIndex) {
            _revert();

            TestMarket storage testMarket = testMarkets[borrowableUnderlyings[marketIndex]];
            reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
            morpho.setReserveFactor(testMarket.underlying, reserveFactor);

            amount = _boundBorrow(testMarket, amount);
            amount = _promoteBorrow(promoter1, testMarket, amount); // 100% peer-to-peer.

            _borrowWithoutCollateral(
                address(user), testMarket, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
            );

            vm.warp(block.timestamp + (365 days));
            uint256 beforeBalance = ERC20(testMarket.underlying).balanceOf(address(morpho));

            Types.Market memory market = morpho.market(testMarket.underlying);
            Types.Deltas memory deltas = market.deltas;
            Types.Indexes256 memory indexes = morpho.updatedIndexes(testMarket.underlying);
            uint256 expectedFeeCollected = deltas.borrow.scaledP2PTotal.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
                deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                    deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)
                )
            );

            uint256 borrowBalance = morpho.borrowBalance(market.underlying, address(user));

            user.approve(market.underlying, borrowBalance);

            user.repay(market.underlying, borrowBalance);

            assertEq(
                ERC20(testMarket.underlying).balanceOf(address(morpho)),
                beforeBalance + expectedFeeCollected,
                "Right amount of fees collected"
            );
        }
    }

    function testRepayFeeWithBorrowDeltaAndP2P(uint16 reserveFactor, uint256 borrowDeltaAmount, uint256 borrowAmount)
        public
    {
        TestMarket storage testMarket = testMarkets[borrowableUnderlyings[0]];
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        morpho.setReserveFactor(testMarket.underlying, reserveFactor);

        _increaseBorrowDelta(promoter1, testMarket, borrowDeltaAmount);
        console.log("delta");
        borrowAmount = _boundBorrow(testMarket, borrowAmount);
        borrowAmount = _promoteBorrow(promoter2, testMarket, borrowAmount);
        console.log("finish");
        borrowAmount = bound(borrowAmount, borrowDeltaAmount, type(uint256).max);
        _borrowWithoutCollateral(
            address(user), testMarket, borrowAmount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );
        console.log("done");
        vm.warp(block.timestamp + (365 days));
        Types.Market memory market = morpho.market(testMarket.underlying);
        Types.Deltas memory deltas = market.deltas;

        uint256 borrowBalance = morpho.borrowBalance(market.underlying, address(user));
        uint256 beforeBalance = ERC20(testMarket.underlying).balanceOf(address(morpho));

        Types.Indexes256 memory indexes = morpho.updatedIndexes(testMarket.underlying);

        vm.assume(borrowBalance > deltas.borrow.scaledDelta);

        uint256 expectedFeeCollected = deltas.borrow.scaledP2PTotal.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            borrowDeltaAmount
                + deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                    deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)
                )
        );

        user.approve(market.underlying, borrowBalance);
        user.repay(market.underlying, borrowBalance);

        assertApproxEqAbs(
            beforeBalance + expectedFeeCollected,
            ERC20(testMarket.underlying).balanceOf(address(morpho)),
            1,
            "Wrong amount of fees"
        );
    }
}
