// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRepay is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    struct RepayTest {
        uint256 borrowed;
        uint256 repaid;
        uint256 balanceBefore;
        uint256 morphoSupplyBefore;
        uint256 scaledP2PBorrow;
        uint256 scaledPoolBorrow;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldRepayPoolOnly(uint256 amount, address onBehalf) public {
        RepayTest memory test;

        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            test.borrowed = _boundBorrow(market, amount);
            uint256 promoted = _promoteBorrow(promoter1, market, test.borrowed.percentMul(50_00)); // 50% peer-to-peer.
            amount = test.borrowed - promoted;

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);
            market.resetPreviousIndex(address(morpho)); // Enable borrow/repay in same block.

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user.repay(market.underlying, amount, onBehalf);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 p2pBorrow = test.scaledP2PBorrow.rayMul(test.indexes.borrow.p2pIndex);
            uint256 poolBorrow = test.scaledPoolBorrow.rayMul(test.indexes.borrow.poolIndex);
            uint256 remaining = test.borrowed - test.repaid;

            // Assert balances on Morpho.
            assertGe(poolBorrow, 0, "poolBorrow == 0");
            assertLe(poolBorrow, remaining, "poolBorrow > remaining");
            assertApproxEqDust(test.repaid, amount, "repaid != amount");
            assertApproxEqDust(p2pBorrow, promoted, "p2pBorrow != promoted");

            // Assert Morpho getters.
            assertApproxEqDust(morpho.borrowBalance(market.underlying, onBehalf), remaining, "borrow != remaining");

            // Assert Morpho's position on pool.
            assertApproxEqAbs(
                market.supplyOf(address(morpho)), test.morphoSupplyBefore, 1, "morphoSupply != morphoSupplyBefore"
            );
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 1, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                test.balanceBefore - user.balanceOf(market.underlying),
                amount,
                1,
                "balanceBefore - balanceAfter != amount"
            );

            // Assert Morpho's market state.
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(
                test.morphoMarket.deltas.supply.scaledTotalP2P,
                test.scaledP2PBorrow,
                "scaledTotalSupplyP2P != scaledP2PBorrow"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(
                test.morphoMarket.deltas.borrow.scaledTotalP2P,
                test.scaledP2PBorrow,
                "scaledTotalBorrowP2P != scaledP2PBorrow"
            );
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldRepayAllBorrow(uint256 amount, address onBehalf) public {
        RepayTest memory test;

        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            test.borrowed = _boundBorrow(market, amount);
            uint256 promoted = _promoteBorrow(promoter1, market, test.borrowed.percentMul(50_00)); // 50% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);
            market.resetPreviousIndex(address(morpho)); // Enable borrow/repay in same block.

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user.repay(market.underlying, amount, onBehalf);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxEqAbs(test.repaid, test.borrowed, 2, "repaid != amount");
            assertEq(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter1)), 0, "promoterScaledP2PSupply != 0"
            );

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), 0, "borrow != 0");
            assertApproxEqDust(
                morpho.supplyBalance(market.underlying, address(promoter1)), promoted, "promoterSupply != promoted"
            );

            // Assert Morpho's position on pool.
            assertApproxEqAbs(
                market.supplyOf(address(morpho)),
                test.morphoSupplyBefore + promoted,
                3,
                "morphoSupply != morphoSupplyBefore + promoted"
            );
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 2, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert user's underlying balance.
            assertApproxLeAbs(
                test.balanceBefore,
                user.balanceOf(market.underlying) + test.repaid,
                2,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            assertApproxEqAbs(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, 2, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    // TODO: combine supply cap exceeded with parts on pool that creates a supply delta?

    function testShouldRepayAllP2PBorrowWhenSupplyCapExceeded(uint256 supplyCap, uint256 amount, address onBehalf)
        public
    {
        RepayTest memory test;

        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            test.borrowed = _boundBorrow(market, amount);
            test.borrowed = _promoteBorrow(promoter1, market, test.borrowed); // 100% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);
            market.resetPreviousIndex(address(morpho)); // Enable borrow/repay in same block.

            supplyCap = _boundSupplyCapExceeded(market, test.borrowed, supplyCap);
            _setSupplyCap(market, supplyCap);

            uint256 supplyGapBefore = _supplyGap(market);
            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user.repay(market.underlying, amount, onBehalf);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxEqDust(test.repaid, test.borrowed, "repaid != amount");

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), 0, "borrow != 0");
            assertEq(
                morpho.supplyBalance(market.underlying, address(promoter1)), test.borrowed, "promoterSupply != borrowed"
            );

            // Assert Morpho's position on pool.
            assertApproxGeAbs(
                market.supplyOf(address(morpho)),
                test.morphoSupplyBefore + supplyGapBefore,
                1,
                "morphoSupply != morphoSupplyBefore + supplyGapBefore"
            );
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 1, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");
            assertEq(_supplyGap(market), 0, "supplyGapAfter != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                test.balanceBefore,
                user.balanceOf(market.underlying) + test.repaid,
                1,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            assertApproxEqAbs(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, 1, "scaledSupplyDelta != 0");
            assertApproxEqAbs(
                test.morphoMarket.deltas.supply.scaledTotalP2P.rayMul(test.indexes.supply.p2pIndex),
                test.borrowed,
                1,
                "scaledTotalSupplyP2P != borrowed"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertApproxGeAbs(test.morphoMarket.idleSupply, test.borrowed, 1, "idleSupply != borrowed");
        }
    }

    function testShouldRepayAllP2PBorrowWhenDemotedZero(uint256 amount, address onBehalf) public {
        RepayTest memory test;

        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            test.borrowed = _boundBorrow(market, amount);
            test.borrowed = _promoteBorrow(promoter1, market, test.borrowed); // 100% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);
            market.resetPreviousIndex(address(morpho)); // Enable borrow/repay in same block.

            // Set the max iterations to 0 upon repay to skip demotion and fallback to supply delta.
            morpho.setDefaultMaxIterations(Types.MaxIterations({repay: 0, withdraw: 10}));

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PSupplyDeltaUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user.repay(market.underlying, amount, onBehalf);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxEqDust(test.repaid, test.borrowed, "repaid != amount");
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter1)),
                0,
                "promoterScaledPoolSupply != 0"
            );

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), 0, "borrow != 0");
            assertEq(
                morpho.supplyBalance(market.underlying, address(promoter1)), test.borrowed, "promoterSupply != borrowed"
            );

            // Assert Morpho's position on pool.
            uint256 morphoSupply = market.supplyOf(address(morpho));
            assertApproxEqAbs(
                morphoSupply,
                test.morphoSupplyBefore + test.borrowed,
                2,
                "morphoSupply != morphoSupplyBefore + borrowed"
            );
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 1, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                test.balanceBefore,
                user.balanceOf(market.underlying) + test.repaid,
                1,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            assertApproxGeAbs(
                test.morphoMarket.deltas.supply.scaledDeltaPool.rayMul(test.indexes.supply.poolIndex),
                test.borrowed,
                1,
                "supplyDelta != borrowed"
            );
            assertEq(
                test.morphoMarket.deltas.supply.scaledTotalP2P.rayMul(test.indexes.supply.p2pIndex),
                test.borrowed,
                "totalSupplyP2P != borrowed"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldRevertRepayZero(address onBehalf) public {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.repay(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertRepayOnBehalfZero(uint256 amount) public {
        amount = _boundAmount(amount);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.repay(testMarkets[underlyings[marketIndex]].underlying, amount, address(0));
        }
    }

    function testShouldRevertRepayWhenMarketNotCreated(address underlying, uint256 amount, address onBehalf) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.assume(underlying != allUnderlyings[i]);
        }

        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.repay(underlying, amount, onBehalf);
    }

    function testShouldRevertRepayWhenRepayPaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket memory market = testMarkets[underlyings[marketIndex]];

            morpho.setIsRepayPaused(market.underlying, true);

            vm.expectRevert(Errors.RepayIsPaused.selector);
            user.repay(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRepayWhenEverythingElsePaused(uint256 borrowed, uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            borrowed = _boundBorrow(market, borrowed);

            _borrowNoCollateral(onBehalf, market, borrowed, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);
            market.resetPreviousIndex(address(morpho)); // Enable borrow/repay in same block.

            morpho.setIsPausedForAllMarkets(true);
            morpho.setIsRepayPaused(market.underlying, false);

            user.approve(market.underlying, amount);
            user.repay(market.underlying, amount, onBehalf);
        }
    }
}
