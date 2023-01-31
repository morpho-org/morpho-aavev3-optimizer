// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;

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
        if (onBehalf != address(user1)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user1), true);
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

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableMarkets[marketIndex]];

            amount = _boundBorrow(market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user1), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 poolBorrow = test.scaledPoolBorrow.rayMul(indexes.borrow.poolIndex);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PBorrow, 0, "p2pBorrow != 0");
            assertEq(test.borrowed, amount, "borrowed != amount");
            assertApproxLeAbs(poolBorrow, amount, 1, "poolBorrow != amount");

            // Assert Morpho getters.
            assertEq(morpho.borrowBalance(market.underlying, onBehalf), poolBorrow, "borrowBalance != poolBorrow");

            // Assert Morpho's position on pool.
            assertApproxLeAbs(
                ERC20(market.debtToken).balanceOf(address(morpho)), test.borrowed, 2, "morphoBorrow != borrowed"
            );

            // Assert receiver's underlying balance.
            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                "balanceAfter - balanceBefore != amount"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
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

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableMarkets[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(market, amount); // 100% peer-to-peer.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);
            uint256 morphoBalanceBefore = ERC20(market.debtToken).balanceOf(address(morpho));

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user1), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 p2pBorrow = test.scaledP2PBorrow.rayMul(test.indexes.supply.p2pIndex);

            // Assert balances on Morpho.
            assertEq(test.scaledPoolBorrow, 0, "poolBorrow != 0");
            assertEq(test.borrowed, amount, "borrowed != amount");
            assertApproxLeAbs(p2pBorrow, amount, 1, "p2pBorrow != amount");
            assertEq(
                morpho.scaledP2PSupplyBalance(market.underlying, address(promoter)),
                test.scaledP2PBorrow,
                "promoterScaledP2PSupply != scaledP2PBorrow"
            );
            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(promoter)), 0, "promoterScaledPoolSupply != 0"
            );

            // Assert Morpho getters.
            assertApproxGeAbs(
                morpho.borrowBalance(market.underlying, onBehalf), p2pBorrow, 1, "borrowBalance != p2pBorrow"
            );
            assertEq(
                morpho.supplyBalance(market.underlying, address(promoter)),
                test.borrowed,
                "promoterSupplyBalance != borrowed"
            );

            // Assert Morpho's position on pool.
            assertApproxGeAbs(
                ERC20(market.debtToken).balanceOf(address(morpho)),
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
            test.morphoMarket = morpho.market(market.underlying);
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

    // TODO: should borrow p2p idle supply

    // TODO: should borrow p2p when supply delta

    // TODO: should not borrow when borrow cap reached

    function testShouldUpdateIndexesAfterBorrow(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableMarkets[marketIndex]];

            amount = _boundBorrow(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS); // 100% pool.

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

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.borrow(testMarkets[markets[marketIndex]].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(testMarkets[markets[marketIndex]].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertBorrowToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(testMarkets[markets[marketIndex]].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertBorrowWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.borrow(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertBorrowWhenBorrowPaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[markets[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user1.borrow(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.borrow(testMarkets[markets[marketIndex]].underlying, amount, onBehalf, receiver);
        }
    }
}
