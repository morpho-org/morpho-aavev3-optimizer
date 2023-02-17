// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    struct BorrowTest {
        uint256 borrowed;
        uint256 balanceBefore;
        uint256 scaledP2PBorrow;
        uint256 scaledPoolBorrow;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function _assertBorrowPool(
        TestMarket storage market,
        uint256 amount,
        address onBehalf,
        address receiver,
        BorrowTest memory test
    ) internal returns (BorrowTest memory) {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
        test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
        uint256 poolBorrow = test.scaledPoolBorrow.rayMul(test.indexes.borrow.poolIndex);

        // Assert balances on Morpho.
        assertEq(test.borrowed, amount, "borrowed != amount");
        assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
        assertApproxEqDust(poolBorrow, amount, "poolBorrow != amount");

        assertApproxEqDust(morpho.borrowBalance(market.underlying, onBehalf), amount, "borrow != amount");

        // Assert Morpho's position on pool.
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), amount, 2, "morphoVariableBorrow != amount");
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert receiver's underlying balance.
        assertEq(
            ERC20(market.underlying).balanceOf(receiver),
            test.balanceBefore + amount,
            "balanceAfter - balanceBefore != amount"
        );

        return test;
    }

    function _assertBorrowP2P(
        TestMarket storage market,
        uint256 amount,
        address onBehalf,
        address receiver,
        BorrowTest memory test
    ) internal returns (BorrowTest memory) {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
        test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
        uint256 p2pBorrow = test.scaledP2PBorrow.rayMul(test.indexes.supply.p2pIndex);

        // Assert balances on Morpho.
        assertEq(test.borrowed, amount, "borrowed != amount");
        assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
        assertApproxEqDust(p2pBorrow, amount, "p2pBorrow != amount");
        assertApproxLeAbs(
            morpho.scaledP2PSupplyBalance(market.underlying, address(promoter1)),
            test.scaledP2PBorrow,
            2,
            "promoterScaledP2PSupply != scaledP2PBorrow"
        );
        assertEq(
            morpho.scaledPoolSupplyBalance(market.underlying, address(promoter1)), 0, "promoterScaledPoolSupply != 0"
        );

        assertApproxEqDust(morpho.borrowBalance(market.underlying, onBehalf), amount, "borrow != amount");
        assertApproxEqDust(
            morpho.supplyBalance(market.underlying, address(promoter1)), amount, "promoterSupply != amount"
        );

        // Assert Morpho's position on pool.
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 2, "morphoVariableBorrow != 0");
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert receiver's underlying balance.
        assertEq(
            ERC20(market.underlying).balanceOf(receiver),
            test.balanceBefore + amount,
            "balanceAfter - balanceBefore != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDelta, 0, "scaledSupplyDelta != 0");
        assertEq(
            test.morphoMarket.deltas.supply.scaledP2PTotal,
            test.scaledP2PBorrow,
            "scaledTotalSupplyP2P != scaledP2PBorrow"
        );
        assertEq(test.morphoMarket.deltas.borrow.scaledDelta, 0, "scaledBorrowDelta != 0");
        assertEq(
            test.morphoMarket.deltas.borrow.scaledP2PTotal,
            test.scaledP2PBorrow,
            "scaledTotalBorrowP2P != scaledP2PBorrow"
        );
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");

        return test;
    }

    function testShouldBorrowPoolOnly(uint256 amount, address onBehalf, address receiver) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowPool(market, amount, onBehalf, receiver, test);

            _assertMarketState(test.morphoMarket);
        }
    }

    function testShouldBorrowP2POnly(uint256 amount, address onBehalf, address receiver) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(promoter1, market, amount); // 100% peer-to-peer.

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowP2P(market, amount, onBehalf, receiver, test);
        }
    }

    function testShouldBorrowP2PWhenIdleSupply(uint256 amount, address onBehalf, address receiver) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseIdleSupply(promoter1, market, amount);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowP2P(market, amount, onBehalf, receiver, test);
        }
    }

    function testShouldBorrowPoolWhenP2PDisabled(uint256 amount, address onBehalf, address receiver) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(promoter1, market, amount); // 100% peer-to-peer.

            morpho.setIsP2PDisabled(market.underlying, true);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowPool(market, amount, onBehalf, receiver, test);

            _assertMarketState(test.morphoMarket);
        }
    }

    function testShouldBorrowP2PWhenSupplyDelta(uint256 amount, address onBehalf, address receiver) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseSupplyDelta(promoter1, market, amount);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.P2PSupplyDeltaUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowP2P(market, amount, onBehalf, receiver, test);
        }
    }

    function testShouldNotBorrowP2PWhenP2PDisabledWithSupplyDelta(
        uint256 supplyDelta,
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            supplyDelta = _increaseSupplyDelta(promoter1, market, supplyDelta);

            morpho.setIsP2PDisabled(market.underlying, true);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowPool(market, amount, onBehalf, receiver, test);

            // Assert Morpho's market state.
            assertApproxEqAbs(
                test.morphoMarket.deltas.supply.scaledDelta.rayMul(test.indexes.supply.poolIndex),
                supplyDelta,
                1,
                "supplyDelta != expectedSupplyDelta"
            );
            assertApproxEqAbs(
                test.morphoMarket.deltas.supply.scaledP2PTotal.rayMul(test.indexes.supply.p2pIndex),
                supplyDelta,
                1,
                "totalSupplyP2P != expectedSupplyDelta"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDelta, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledP2PTotal, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldNotBorrowP2PWhenP2PDisabledWithIdleSupply(
        uint256 idleSupply,
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        BorrowTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            idleSupply = _increaseIdleSupply(promoter1, market, idleSupply);

            morpho.setIsP2PDisabled(market.underlying, true);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            test.borrowed =
                _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test = _assertBorrowPool(market, amount, onBehalf, receiver, test);

            // Assert Morpho's market state.
            assertEq(test.morphoMarket.deltas.supply.scaledDelta, 0, "scaledSupplyDelta != 0");
            assertApproxEqAbs(
                test.morphoMarket.deltas.supply.scaledP2PTotal.rayMul(test.indexes.supply.p2pIndex),
                idleSupply,
                1,
                "totalSupplyP2P != expectedIdleSupply"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDelta, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledP2PTotal, 0, "scaledTotalBorrowP2P != 0");
            assertApproxEqDust(test.morphoMarket.idleSupply, idleSupply, "idleSupply != expectedIdleSupply");
        }
    }

    function testShouldNotBorrowWhenBorrowCapExceeded(
        uint256 amount,
        address onBehalf,
        address receiver,
        uint256 borrowCap,
        uint256 promoted
    ) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            promoted = _promoteBorrow(promoter1, market, bound(promoted, 1, amount)); // <= 100% peer-to-peer.

            // Set the borrow cap so that the borrow gap is lower than the amount borrowed on pool.
            borrowCap = _boundBorrowCapExceeded(market, amount - promoted, borrowCap);
            _setBorrowCap(market, borrowCap);

            vm.expectRevert(Errors.ExceedsBorrowCap.selector);
            user.borrow(market.underlying, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);
        }
    }

    function testShouldNotBorrowMoreThanLtv(uint256 collateral, uint256 borrowed, address onBehalf, address receiver)
        public
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (
            uint256 collateralMarketIndex; collateralMarketIndex < collateralUnderlyings.length; ++collateralMarketIndex
        ) {
            for (uint256 borrowedMarketIndex; borrowedMarketIndex < borrowableUnderlyings.length; ++borrowedMarketIndex)
            {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralMarketIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedMarketIndex]];

                collateral = _boundCollateral(collateralMarket, collateral, borrowedMarket);
                borrowed = bound(
                    borrowed,
                    borrowedMarket.borrowable(collateralMarket, collateral).percentAdd(2),
                    2 * borrowedMarket.maxAmount
                );
                _promoteBorrow(promoter1, borrowedMarket, borrowed); // <= 100% peer-to-peer.

                user.approve(collateralMarket.underlying, collateral);
                user.supplyCollateral(collateralMarket.underlying, collateral, onBehalf);

                vm.expectRevert(Errors.UnauthorizedBorrow.selector);
                user.borrow(borrowedMarket.underlying, borrowed, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);
            }
        }
    }

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

            _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS); // 100% pool.

            _assertUpdateIndexes(morpho.market(market.underlying), futureIndexes);
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

    function testShouldRevertBorrowWhenMarketNotCreated(
        address underlying,
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        _assumeNotUnderlying(underlying);

        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.borrow(underlying, amount, onBehalf, receiver);
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

    function testShouldBorrowWhenEverythingElsePaused(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        morpho.setIsPausedForAllMarkets(true);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            morpho.setIsBorrowPaused(market.underlying, false);

            _borrowWithoutCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);
        }
    }
}
