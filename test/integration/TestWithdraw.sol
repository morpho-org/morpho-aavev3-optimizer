// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdraw is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
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

    struct WithdrawTest {
        uint256 supplied;
        uint256 withdrawn;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldWithdrawPoolOnly(uint256 amount, address onBehalf, address receiver)
        public
        returns (WithdrawTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            test.supplied = _boundSupply(market, amount);
            uint256 promoted = _promoteSupply(promoter1, market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
            amount = test.supplied - promoted;

            user.approve(market.underlying, test.supplied);
            user.supply(market.underlying, test.supplied, onBehalf);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(address(user), onBehalf, receiver, market.underlying, amount, 0, 0);

            test.withdrawn = user.withdraw(market.underlying, amount, onBehalf, receiver);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
            uint256 p2pSupply = test.scaledP2PSupply.rayMul(test.indexes.supply.p2pIndex);
            uint256 remaining = test.supplied - test.withdrawn;

            // Assert balances on Morpho.
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertApproxLeAbs(test.withdrawn, amount, 1, "withdrawn != amount");
            assertApproxLeAbs(p2pSupply, promoted, 2, "p2pSupply != promoted");

            assertApproxLeAbs(morpho.supplyBalance(market.underlying, onBehalf), remaining, 1, "supply != remaining");
            assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");

            // Assert Morpho's position on pool.
            assertApproxEqAbs(market.supplyOf(address(morpho)), 0, 1, "morphoSupply != 0");
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 2, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert receiver's underlying balance.
            assertApproxEqAbs(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                1,
                "balanceAfter - balanceBefore != amount"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(
                test.morphoMarket.deltas.supply.scaledTotalP2P,
                test.scaledP2PSupply,
                "scaledTotalSupplyP2P != scaledP2PSupply"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(
                test.morphoMarket.deltas.borrow.scaledTotalP2P,
                test.scaledP2PSupply,
                "scaledTotalBorrowP2P != scaledP2PSupply"
            );
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldWithdrawAllSupply(uint256 amount, address onBehalf, address receiver)
        public
        returns (WithdrawTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            test.supplied = _boundSupply(market, amount);
            test.supplied = bound(test.supplied, 0, market.liquidity()); // Because >= 50% will get borrowed from the pool.
            uint256 promoted = _promoteSupply(promoter1, market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
            amount = bound(amount, test.supplied + 1, type(uint256).max);

            user.approve(market.underlying, test.supplied);
            user.supply(market.underlying, test.supplied, onBehalf);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            if (promoted > 0) {
                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.BorrowPositionUpdated(address(promoter1), market.underlying, 0, 0);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.P2PTotalsUpdated(market.underlying, 0, 0);
            }

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(address(user), onBehalf, receiver, market.underlying, test.supplied, 0, 0);

            test.withdrawn = user.withdraw(market.underlying, amount, onBehalf, receiver);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertApproxLeAbs(test.withdrawn, test.supplied, 2, "withdrawn != supplied");
            assertEq(
                morpho.scaledP2PBorrowBalance(market.underlying, address(promoter1)), 0, "promoterScaledP2PBorrow != 0"
            );

            // Assert Morpho getters.
            assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "supply != 0");
            assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");
            assertApproxGeAbs(
                morpho.borrowBalance(market.underlying, address(promoter1)), promoted, 3, "promoterBorrow != promoted"
            );

            // Assert Morpho's position on pool.
            assertApproxEqAbs(market.supplyOf(address(morpho)), 0, 2, "morphoSupply != 0");
            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), promoted, 2, "morphoVariableBorrow != promoted");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert receiver's underlying balance.
            assertApproxLeAbs(
                ERC20(market.underlying).balanceOf(receiver),
                balanceBefore + test.withdrawn,
                2,
                "balanceAfter != balanceBefore + withdrawn"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertApproxEqAbs(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, 1, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertApproxEqAbs(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, 1, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldWithdrawAllP2PSupplyWhenBorrowCapExceededWithIdleSupply(
        uint256 borrowCap,
        uint256 amount,
        address onBehalf,
        address receiver
    ) public returns (WithdrawTest memory test) {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            test.supplied = _boundSupply(market, amount);
            test.supplied = _promoteSupply(promoter1, market, test.supplied); // 100% peer-to-peer.
            amount = bound(amount, test.supplied + 1, type(uint256).max);

            user.approve(market.underlying, test.supplied);
            user.supply(market.underlying, test.supplied, onBehalf);

            _increaseIdleSupply(promoter2, market, test.supplied);

            // Set the borrow cap so that the borrow gap is lower than the amount withdrawn.
            borrowCap = bound(borrowCap, 10 ** market.decimals, market.totalBorrow() + test.supplied);
            _setBorrowCap(market, borrowCap);

            uint256 borrowGapBefore = market.borrowGap();
            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.withdrawn = user.withdraw(market.underlying, amount, onBehalf, receiver);

            test.indexes = morpho.updatedIndexes(market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertApproxLeAbs(test.withdrawn, test.supplied, 2, "withdrawn != supplied");
            assertEq(
                morpho.scaledPoolBorrowBalance(market.underlying, address(promoter1)),
                0,
                "promoter1ScaledP2PBorrow != 0"
            );
            assertEq(
                morpho.scaledPoolBorrowBalance(market.underlying, address(promoter2)),
                0,
                "promoter2ScaledPoolBorrow != 0"
            );

            // Assert Morpho getters.
            assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "supply != 0");
            assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");
            assertApproxGeAbs(
                morpho.borrowBalance(market.underlying, address(promoter1)),
                test.supplied,
                3,
                "promoter1Borrow != supplied"
            );
            assertApproxLeAbs(
                morpho.supplyBalance(market.underlying, address(promoter2)),
                test.supplied,
                2,
                "promoter2Supply != supplied"
            );

            // Assert Morpho's position on pool.
            assertApproxEqAbs(market.supplyOf(address(morpho)), 0, 1, "morphoSupply != 0");
            assertApproxGeAbs(
                market.variableBorrowOf(address(morpho)), borrowGapBefore, 1, "morphoVariableBorrow != borrowGapBefore"
            );
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");
            assertEq(market.borrowGap(), 0, "borrowGapAfter != 0");

            // Assert user's underlying balance.
            assertApproxLeAbs(
                ERC20(market.underlying).balanceOf(receiver),
                balanceBefore + test.withdrawn,
                2,
                "balanceAfter != balanceBefore + withdrawn"
            );

            // Assert Morpho's market state.
            test.morphoMarket = morpho.market(market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(
                test.morphoMarket.deltas.supply.scaledTotalP2P.rayMul(test.indexes.supply.p2pIndex),
                test.supplied,
                "scaledTotalSupplyP2P != supplied"
            );
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(
                test.morphoMarket.deltas.borrow.scaledTotalP2P.rayMul(test.indexes.borrow.p2pIndex),
                test.supplied,
                "scaledTotalBorrowP2P != supplied"
            );
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    // TODO: should withdraw when not enough suppliers

    function testShouldNotWithdrawWhenNoSupply(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            uint256 withdrawn = user.withdraw(market.underlying, amount, onBehalf, receiver);

            uint256 balanceAfter = ERC20(market.underlying).balanceOf(receiver);

            assertEq(withdrawn, 0, "withdrawn != 0");
            assertEq(balanceAfter, balanceBefore, "balanceAfter != balanceBefore");
        }
    }

    function testShouldUpdateIndexesAfterWithdraw(uint256 amount, address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            user.withdraw(market.underlying, type(uint256).max);

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

    function testShouldRevertWithdrawZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.withdraw(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.withdraw(testMarkets[underlyings[marketIndex]].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertWithdrawToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.withdraw(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.withdraw(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawWhenWithdrawPaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsWithdrawPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawIsPaused.selector);
            user.withdraw(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user.withdraw(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldWithdrawWhenEverythingElsePaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            user.approve(market.underlying, amount);
            user.supply(market.underlying, amount);

            morpho.setIsPausedForAllMarkets(true);
            morpho.setIsWithdrawPaused(market.underlying, false);

            user.withdraw(market.underlying, amount);
        }
    }
}
