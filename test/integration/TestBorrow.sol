// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;
    using TestMarketLib for TestMarket;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.assume(onBehalf != address(proxyAdmin)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target

        return onBehalf;
    }

    function _boundReceiver(address receiver) internal view returns (address) {
        return address(uint160(bound(uint256(uint160(receiver)), 1, type(uint160).max)));
    }

    function _prepareOnBehalf(address onBehalf) internal {
        if (onBehalf != address(user)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user), true);
        }
    }

    struct BorrowTest {
        uint256 borrowed;
        uint256 scaledP2PBorrow;
        uint256 scaledPoolBorrow;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldBorrowPoolOnly(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 poolBorrow = test.scaledPoolBorrow.rayMulUp(test.indexes.borrow.poolIndex);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
            assertEq(test.borrowed, amount, "borrowed != amount");
            assertApproxGeAbs(poolBorrow, amount, 2, "poolBorrow != amount");

            assertApproxGeAbs(morpho.borrowBalance(market.underlying, onBehalf), amount, 2, "borrow != amount");

            // Assert Morpho's position on pool.
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), amount, 1, "morphoVariableBorrow != amount");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert receiver's underlying balance.
            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                "balanceAfter - balanceBefore != amount"
            );

            // Assert Morpho's market state.
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldBorrowP2POnly(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(promoter1, market, amount); // 100% peer-to-peer.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);
            uint256 morphoBalanceBefore = market.variableBorrowOf(address(morpho));

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 p2pBorrow = test.scaledP2PBorrow.rayMulUp(test.indexes.supply.p2pIndex);

            // Assert balances on Morpho.
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertEq(test.borrowed, amount, "borrowed != amount");
            assertApproxGeAbs(p2pBorrow, amount, 1, "p2pBorrow != amount");
            assertApproxLeAbs(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter1)),
                test.scaledP2PBorrow,
                2,
                "promoterScaledP2PSupply != scaledP2PBorrow"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter1)),
                0,
                "promoterScaledPoolSupply != 0"
            );

            assertApproxGeAbs(morpho.borrowBalance(market.underlying, onBehalf), amount, 2, "borrow != amount");
            assertApproxLeAbs(
                morpho.supplyBalance(market.underlying, address(promoter1)), amount, 2, "promoterSupply != amount"
            );

            // Assert Morpho's position on pool.
            assertApproxGeAbs(
                market.variableBorrowOf(address(morpho)),
                morphoBalanceBefore,
                2,
                "morphoBalanceAfter != morphoBalanceBefore"
            );

            // Assert receiver's underlying balance.
            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                "balanceAfter - balanceBefore != amount"
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

    function testShouldBorrowP2PWhenIdleSupply(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseIdleSupply(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test.morphoMarket = morpho.market(market.underlying);
            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 p2pBorrow = test.scaledP2PBorrow.rayMulUp(test.indexes.borrow.p2pIndex);

            // Assert balances on Morpho.
            assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
            assertEq(test.borrowed, amount, "borrowed != amount");
            assertApproxGeAbs(p2pBorrow, amount, 1, "p2pBorrow != amount");
            assertApproxLeAbs(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter1)),
                test.scaledP2PBorrow,
                2,
                "promoterScaledP2PSupply != scaledP2PBorrow"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter1)),
                0,
                "promoterScaledPoolSupply != 0"
            );

            // // Assert Morpho getters.
            // assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "supply != 0");
            // assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");
            // assertApproxGeAbs(
            //     morpho.borrowBalance(market.underlying, address(promoter1)),
            //     test.supplied,
            //     3,
            //     "promoter1Borrow != supplied"
            // );
            // assertApproxLeAbs(
            //     morpho.supplyBalance(market.underlying, address(promoter2)),
            //     test.supplied,
            //     2,
            //     "promoter2Supply != supplied"
            // );

            // // Assert Morpho's position on pool.
            // assertApproxEqAbs(market.supplyOf(address(morpho)), 0, 1, "morphoSupply != 0");
            // assertApproxGeAbs(
            //     market.variableBorrowOf(address(morpho)), borrowGapBefore, 1, "morphoVariableBorrow != borrowGapBefore"
            // );
            // assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");
            // assertEq(market.borrowGap(), 0, "borrowGapAfter != 0");

            // // Assert user's underlying balance.
            // assertApproxLeAbs(
            //     ERC20(market.underlying).balanceOf(receiver),
            //     balanceBefore + test.withdrawn,
            //     2,
            //     "balanceAfter != balanceBefore + withdrawn"
            // );

            // // Assert Morpho's market state.
            // assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            // assertEq(
            //     test.morphoMarket.deltas.supply.scaledTotalP2P.rayMul(test.indexes.supply.p2pIndex),
            //     test.supplied,
            //     "scaledTotalSupplyP2P != supplied"
            // );
            // assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            // assertEq(
            //     test.morphoMarket.deltas.borrow.scaledTotalP2P.rayMul(test.indexes.borrow.p2pIndex),
            //     test.supplied,
            //     "scaledTotalBorrowP2P != supplied"
            // );
            // assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    // TODO: should borrow p2p when supply delta

    // TODO: should not borrow when borrow cap reached

    // TODO: should borrow pool only when p2p disabled

    // TODO: should not borrow p2p when p2p disabled & supply delta

    // TODO: should not borrow p2p when p2p disabled & idle supply

    // TODO: should not borrow more than ltv allows

    function testShouldUpdateIndexesAfterBorrow(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS); // 100% pool.

            Types.Market memory morphoMarket = morpho.market(market.underlying);
            assertEq(
                morphoMarket.indexes.supply.poolIndex,
                futureIndexes.supply.poolIndex,
                "poolSupplyIndex != futurePoolSupplyIndex"
            );
            assertEq(
                morphoMarket.indexes.borrow.poolIndex,
                futureIndexes.borrow.poolIndex,
                "poolBorrowIndex != futurePoolBorrowIndex"
            );

            assertEq(
                morphoMarket.indexes.supply.p2pIndex,
                futureIndexes.supply.p2pIndex,
                "p2pSupplyIndex != futureP2PSupplyIndex"
            );
            assertEq(
                morphoMarket.indexes.borrow.p2pIndex,
                futureIndexes.borrow.p2pIndex,
                "p2pBorrowIndex != futureP2PBorrowIndex"
            );
        }
    }

    function testShouldRevertBorrowZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertBorrowToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertBorrowWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.borrow(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertBorrowWhenBorrowPaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user.borrow(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, receiver);
        }
    }
}
