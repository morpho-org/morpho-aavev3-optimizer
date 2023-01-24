// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdraw is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

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

    struct WithdrawTest {
        uint256 supplied;
        uint256 promoted;
        uint256 withdrawn;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        TestMarket market;
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

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            test.market = markets[marketIndex];

            test.supplied = _boundSupply(test.market, amount);
            test.promoted = _promoteSupply(test.market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
            amount = test.supplied - test.promoted;

            user1.approve(test.market.underlying, test.supplied);
            user1.supply(test.market.underlying, test.supplied, onBehalf);

            uint256 balanceBefore = ERC20(test.market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(address(user1), onBehalf, receiver, test.market.underlying, amount, 0, 0);

            test.withdrawn = user1.withdraw(test.market.underlying, amount, onBehalf, receiver);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(test.market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(test.market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(test.market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(test.market.underlying, onBehalf);
            uint256 p2pSupply = test.scaledP2PSupply.rayMul(indexes.supply.p2pIndex);
            uint256 poolSupply = test.scaledPoolSupply.rayMul(indexes.supply.poolIndex);

            if (test.promoted == 0) {
                assertEq(poolSupply, 0, "poolSupply != 0");
            } else {
                assertGe(poolSupply, 0, "poolSupply == 0");
                assertLe(poolSupply, test.supplied - test.withdrawn, "poolSupply > supplied - withdrawn");
            }

            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertLe(test.withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(test.withdrawn, amount, 1, "withdrawn != amount");
            assertLe(p2pSupply, test.promoted, "p2pSupply > promoted");
            assertApproxEqAbs(p2pSupply, test.promoted, 2, "p2pSupply != promoted");

            uint256 morphoBalanceAfter = ERC20(test.market.aToken).balanceOf(address(morpho));
            assertApproxEqAbs(morphoBalanceAfter, 0, 1, "morphoBalanceAfter != 0");

            assertApproxEqAbs(
                ERC20(test.market.underlying).balanceOf(receiver) - balanceBefore,
                amount,
                1,
                "balanceAfter - balanceBefore != amount"
            );

            test.morphoMarket = morpho.market(test.market.underlying);
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

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            test.market = markets[marketIndex];

            test.supplied = _boundSupply(test.market, amount);
            test.supplied = bound(test.supplied, 0, ERC20(test.market.underlying).balanceOf(test.market.aToken)); // Because >= 50% will get borrowed from the pool.
            uint256 promoted = _promoteSupply(test.market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
            amount = bound(amount, test.supplied + 1, type(uint256).max);

            user1.approve(test.market.underlying, test.supplied);
            user1.supply(test.market.underlying, test.supplied, onBehalf);

            uint256 balanceBefore = ERC20(test.market.underlying).balanceOf(receiver);

            if (promoted > 0) {
                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.BorrowPositionUpdated(address(promoter), test.market.underlying, 0, 0);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.P2PTotalsUpdated(test.market.underlying, 0, 0);
            }

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(address(user1), onBehalf, receiver, test.market.underlying, test.supplied, 0, 0);

            test.withdrawn = user1.withdraw(test.market.underlying, amount, onBehalf, receiver);

            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(test.market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(test.market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(test.market.underlying, onBehalf);

            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertLe(test.withdrawn, test.supplied, "withdrawn > supplied");
            assertApproxEqAbs(test.withdrawn, test.supplied, 2, "withdrawn != supplied");

            assertEq(morpho.supplyBalance(test.market.underlying, onBehalf), 0, "supply != 0");
            assertEq(morpho.collateralBalance(test.market.underlying, onBehalf), 0, "collateral != 0");

            uint256 balanceAfter = ERC20(test.market.underlying).balanceOf(receiver);
            uint256 expectedBalance = balanceBefore + test.withdrawn;
            assertLe(balanceAfter, expectedBalance, "balanceAfter > expectedBalance");
            assertApproxEqAbs(balanceAfter, expectedBalance, 2, "balanceAfter != expectedBalance");

            test.morphoMarket = morpho.market(test.market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    // TODO: add delta withdraw test

    function testShouldNotWithdrawWhenNoSupply(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            uint256 withdrawn = user1.withdraw(market.underlying, amount, onBehalf, receiver);

            uint256 balanceAfter = ERC20(market.underlying).balanceOf(receiver);

            assertEq(withdrawn, 0, "withdrawn != 0");
            assertEq(balanceAfter, balanceBefore, "balanceAfter != balanceBefore");
        }
    }

    function testShouldUpdateIndexesAfterWithdraw(uint256 amount, address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            user1.withdraw(market.underlying, type(uint256).max);

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

    // TODO: add delta tests

    function testShouldRevertWithdrawZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertWithdrawToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdraw(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawWhenWithdrawPaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawIsPaused.selector);
            user1.withdraw(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldWithdrawWhenEverythingElsePaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount);

            morpho.setIsPausedForAllMarkets(true);
            morpho.setIsWithdrawPaused(market.underlying, false);

            user1.withdraw(market.underlying, amount);
        }
    }
}
