// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRepay is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    struct RepayTest {
        uint256 borrowed;
        uint256 repaid;
        uint256 scaledP2PBorrow;
        uint256 scaledPoolBorrow;
        TestMarket market;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldRepayPoolOnly(uint256 amount, address onBehalf) public returns (RepayTest memory test) {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            test.market = borrowableMarkets[marketIndex];

            test.borrowed = _boundBorrow(test.market, amount);
            uint256 promoted = _promoteBorrow(test.market, test.borrowed.percentMul(50_00)); // 50% peer-to-peer.
            amount = test.borrowed - promoted;

            _borrowNoCollateral(onBehalf, test.market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_LOOPS);
            _resetPreviousIndex(test.market); // Enable borrow/repay in same block.

            uint256 balanceBefore = user1.balanceOf(test.market.underlying);

            user1.approve(test.market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user1), onBehalf, test.market.underlying, 0, 0, 0);

            test.repaid = user1.repay(test.market.underlying, amount, onBehalf);

            test.indexes = morpho.updatedIndexes(test.market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(test.market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(test.market.underlying, onBehalf);
            uint256 p2pBorrow = test.scaledP2PBorrow.rayMul(test.indexes.borrow.p2pIndex);
            uint256 poolBorrow = test.scaledPoolBorrow.rayMul(test.indexes.borrow.poolIndex);

            // Assert balances on Morpho.
            assertGe(poolBorrow, 0, "poolBorrow == 0");
            assertLe(poolBorrow, test.borrowed - test.repaid, "poolBorrow > borrowed - repaid");
            assertApproxLeAbs(test.repaid, amount, 1, "repaid != amount");
            assertApproxLeAbs(p2pBorrow, promoted, 2, "p2pBorrow != promoted");

            // Assert Morpho getters.
            assertApproxGeAbs(
                morpho.borrowBalance(test.market.underlying, onBehalf),
                test.borrowed - test.repaid,
                1,
                "borrowBalance != borrowed - repaid"
            );

            // Assert Morpho's position on pool.
            assertApproxEqAbs(ERC20(test.market.aToken).balanceOf(address(morpho)), 0, 1, "morphoSupply != 0");
            assertApproxEqAbs(ERC20(test.market.debtToken).balanceOf(address(morpho)), 0, 1, "morphoBorrow != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                balanceBefore - user1.balanceOf(test.market.underlying),
                amount,
                1,
                "balanceBefore - balanceAfter != amount"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(test.market.underlying);
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

    function testShouldRepayAllBorrow(uint256 amount, address onBehalf) public returns (RepayTest memory test) {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            test.market = borrowableMarkets[marketIndex];

            test.borrowed = _boundBorrow(test.market, amount);
            uint256 promoted = _promoteBorrow(test.market, test.borrowed.percentMul(50_00)); // 50% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, test.market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_LOOPS);
            _resetPreviousIndex(test.market); // Enable borrow/repay in same block.

            uint256 balanceBefore = user1.balanceOf(test.market.underlying);

            user1.approve(test.market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter), test.market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(test.market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user1), onBehalf, test.market.underlying, 0, 0, 0);

            test.repaid = user1.repay(test.market.underlying, amount, onBehalf);

            test.indexes = morpho.updatedIndexes(test.market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(test.market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(test.market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxGeAbs(test.repaid, test.borrowed, 1, "repaid != amount");
            assertEq(
                morpho.scaledP2PSupplyBalance(test.market.underlying, address(promoter)),
                0,
                "promoterScaledP2PSupply != 0"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(test.market.underlying, address(promoter)).rayMul(
                    test.indexes.supply.poolIndex
                ),
                promoted,
                "promoterPoolSupply != promoted"
            );

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(test.market.underlying, onBehalf), 0, "borrowBalance != 0");
            assertEq(
                morpho.supplyBalance(test.market.underlying, address(promoter)),
                promoted,
                "promoterSupplyBalance != promoted"
            );

            // Assert Morpho's position on pool.
            assertApproxGeAbs(
                ERC20(test.market.aToken).balanceOf(address(morpho)), promoted, 1, "morphoSupply != promoted"
            );
            assertApproxEqAbs(ERC20(test.market.debtToken).balanceOf(address(morpho)), 0, 1, "morphoBorrow != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                balanceBefore,
                user1.balanceOf(test.market.underlying) + test.repaid,
                1,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(test.market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldRepayAllP2PBorrowWhenSupplyCapLow(uint256 supplyCap, uint256 amount, address onBehalf)
        public
        returns (RepayTest memory test)
    {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = borrowableMarkets[marketIndex];

            test.borrowed = _boundBorrow(market, amount);
            test.borrowed = _promoteBorrow(market, test.borrowed); // 100% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_LOOPS);
            _resetPreviousIndex(market); // Enable borrow/repay in same block.

            // Set the supply cap so that the supply gap is lower than the amount borrowed.
            supplyCap =
                bound(supplyCap, 1, (ERC20(market.aToken).totalSupply() + test.borrowed) / (10 ** market.decimals));
            market.supplyCap = supplyCap * 10 ** market.decimals;
            poolAdmin.setSupplyCap(market.underlying, supplyCap);

            uint256 supplyGapBefore = _supplyGap(market);
            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user1), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user1.repay(market.underlying, amount, onBehalf);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxGeAbs(test.repaid, test.borrowed, 1, "repaid != amount");
            assertEq(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter)), 0, "promoterScaledP2PSupply != 0"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter)).rayMul(
                    test.indexes.supply.poolIndex
                ),
                test.borrowed,
                "promoterPoolSupply != borrowed"
            );

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), 0, "borrowBalance != 0");
            assertEq(
                morpho.supplyBalance(market.underlying, address(promoter)),
                test.borrowed,
                "promoterSupplyBalance != borrowed"
            );

            // Assert Morpho's position on pool.
            assertApproxGeAbs(
                ERC20(market.aToken).balanceOf(address(morpho)), supplyGapBefore, 1, "morphoSupply != supplyGapBefore"
            );
            assertApproxEqAbs(ERC20(market.debtToken).balanceOf(address(morpho)), 0, 1, "morphoBorrow != 0");
            assertEq(_supplyGap(market), 0, "supplyGapAfter != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                balanceBefore,
                user1.balanceOf(market.underlying) + test.repaid,
                1,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, test.borrowed, "idleSupply != borrowed");
        }
    }

    function testShouldRepayAllP2PBorrowWhenMaxLoopsZero(uint256 amount, address onBehalf)
        public
        returns (RepayTest memory test)
    {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = borrowableMarkets[marketIndex];

            test.borrowed = _boundBorrow(market, amount);
            test.borrowed = _promoteBorrow(market, test.borrowed); // 100% peer-to-peer.
            amount = bound(amount, test.borrowed + 1, type(uint256).max);

            _borrowNoCollateral(onBehalf, market, test.borrowed, onBehalf, onBehalf, DEFAULT_MAX_LOOPS);
            _resetPreviousIndex(market); // Enable borrow/repay in same block.

            // Set the supply cap so that the supply gap is lower than the amount borrowed.
            morpho.setDefaultMaxLoops(Types.MaxLoops({repay: 0, withdraw: 10}));

            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PSupplyDeltaUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user1), onBehalf, market.underlying, 0, 0, 0);

            test.repaid = user1.repay(market.underlying, amount, onBehalf);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertApproxGeAbs(test.repaid, test.borrowed, 1, "repaid != amount");
            assertEq(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter)).rayMul(test.indexes.supply.p2pIndex),
                test.borrowed,
                "promoterP2PSupply != borrowed"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter)), 0, "promoterScaledPoolSupply != 0"
            );

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), 0, "borrowBalance != 0");
            assertEq(
                morpho.supplyBalance(market.underlying, address(promoter)),
                test.borrowed,
                "promoterSupplyBalance != borrowed"
            );

            // Assert Morpho's position on pool.
            // assertApproxGeAbs(
            //     ERC20(market.aToken).balanceOf(address(morpho)), supplyGapBefore, 1, "morphoSupply != supplyGapBefore"
            // );
            assertApproxEqAbs(ERC20(market.debtToken).balanceOf(address(morpho)), 0, 1, "morphoBorrow != 0");

            // Assert user's underlying balance.
            assertApproxEqAbs(
                balanceBefore,
                user1.balanceOf(market.underlying) + test.repaid,
                1,
                "balanceBefore != balanceAfter + repaid"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
            assertEq(
                test.morphoMarket.deltas.supply.scaledDeltaPool.rayMul(test.indexes.supply.poolIndex),
                test.borrowed,
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

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.repay(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertRepayOnBehalfZero(uint256 amount) public {
        amount = _boundAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.repay(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertRepayWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.repay(sAvax, amount, onBehalf);
    }

    function testShouldRevertRepayWhenRepayPaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);
        vm.assume(onBehalf != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsRepayPaused(market.underlying, true);

            vm.expectRevert(Errors.RepayIsPaused.selector);
            user1.repay(market.underlying, amount, onBehalf);
        }
    }
}
