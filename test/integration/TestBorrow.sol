// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        vm.assume(onBehalf != address(this)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target

        return address(uint160(bound(uint256(uint160(onBehalf)), 1, type(uint160).max)));
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

    function testShouldBorrowPoolOnly(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            amount = _boundBorrow(market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user1), onBehalf, receiver, market.underlying, 0, 0, 0);

            uint256 borrowed =
                _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_LOOPS);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 poolBorrow =
                morpho.scaledPoolBorrowBalance(market.underlying, onBehalf).rayMul(indexes.borrow.poolIndex);
            uint256 scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);

            assertEq(scaledP2PBorrow, 0, "p2pBorrow != 0");
            assertEq(borrowed, amount, "borrowed != amount");
            assertLe(poolBorrow, amount, "poolBorrow > amount");
            assertApproxEqAbs(poolBorrow, amount, 1, "poolBorrow != amount");

            assertEq(morpho.borrowBalance(market.underlying, onBehalf), poolBorrow, "totalBorrow != poolBorrow");

            // uint256 morphoBalance = ERC20(market.debtToken).balanceOf(address(morpho));
            // assertApproxEqAbs(morphoBalance, borrowed, 1, "morphoBalance != borrowed");

            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                "balanceAfter - balanceBefore != amount"
            );

            Types.Market memory morphoMarket = morpho.market(market.underlying);
            assertEq(morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldBorrowP2POnly(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            amount = _boundBorrow(market, _boundSupply(market, amount)); // Don't go over the supply cap.

            promoter.approve(market.underlying, amount);
            promoter.supply(market.underlying, amount); // 100% peer-to-peer.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);
            uint256 morphoBalanceBefore = ERC20(market.debtToken).balanceOf(address(morpho));

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user1), onBehalf, receiver, market.underlying, 0, 0, 0);

            uint256 borrowed =
                _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_LOOPS);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
            uint256 scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
            uint256 p2pBorrow = scaledP2PBorrow.rayMul(indexes.supply.p2pIndex);

            assertEq(scaledPoolBorrow, 0, "poolBorrow != 0");
            assertEq(borrowed, amount, "borrowed != amount");
            assertLe(p2pBorrow, amount, "p2pBorrow > amount");
            assertApproxEqAbs(p2pBorrow, amount, 1, "p2pBorrow != amount");

            assertEq(morpho.borrowBalance(market.underlying, onBehalf), p2pBorrow, "totalBorrow != p2pBorrow");

            uint256 morphoBalanceAfter = ERC20(market.debtToken).balanceOf(address(morpho));
            assertApproxEqAbs(morphoBalanceAfter, morphoBalanceBefore, 2, "morphoBalanceAfter != morphoBalanceBefore");
            assertGe(morphoBalanceAfter, morphoBalanceBefore, "morphoBalanceAfter < morphoBalanceBefore");

            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                "balanceAfter - balanceBefore != amount"
            );

            Types.Market memory morphoMarket = morpho.market(market.underlying);
            assertEq(morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(
                morphoMarket.deltas.supply.scaledTotalP2P, scaledP2PBorrow, "scaledTotalSupplyP2P != scaledP2PBorrow"
            );
            assertEq(morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(
                morphoMarket.deltas.borrow.scaledTotalP2P, scaledP2PBorrow, "scaledTotalBorrowP2P != scaledP2PBorrow"
            );
            assertEq(morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldUpdateIndexesAfterBorrow(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            amount = _boundBorrow(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            _borrowNoCollateral(address(user1), market, amount, onBehalf, receiver, DEFAULT_MAX_LOOPS); // 100% pool.

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

    // TODO: add idle supply match test
    // TODO: add supply delta match test

    function testShouldRevertBorrowZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertBorrowToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, amount, onBehalf, address(0));
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

            TestMarket memory market = markets[marketIndex];

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
            user1.borrow(markets[marketIndex].underlying, amount, onBehalf, receiver);
        }
    }
}
