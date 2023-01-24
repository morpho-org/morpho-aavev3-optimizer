// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSupply is IntegrationTest {
    using WadRayMath for uint256;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        return address(uint160(bound(uint256(uint160(onBehalf)), 1, type(uint160).max)));
    }

    struct SupplyTest {
        uint256 supplied;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        TestMarket market;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldSupplyPoolOnly(uint256 amount, address onBehalf) public returns (SupplyTest memory test) {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            test.market = markets[marketIndex];

            amount = _boundSupply(test.market, amount);

            uint256 balanceBefore = user1.balanceOf(test.market.underlying);

            user1.approve(test.market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user1), onBehalf, test.market.underlying, 0, 0, 0);

            test.supplied = user1.supply(test.market.underlying, amount, onBehalf); // 100% pool.

            test.indexes = morpho.updatedIndexes(test.market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(test.market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(test.market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(test.market.underlying, onBehalf);
            uint256 poolSupply = test.scaledPoolSupply.rayMul(test.indexes.supply.poolIndex);

            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertEq(test.supplied, amount, "supplied != amount");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertApproxEqAbs(poolSupply, amount, 1, "poolSupply != amount");

            assertEq(morpho.supplyBalance(test.market.underlying, onBehalf), poolSupply, "totalSupply != poolSupply"); // TODO: unit test getters
            assertEq(morpho.collateralBalance(test.market.underlying, onBehalf), 0, "collateral != 0");

            uint256 morphoBalance = ERC20(test.market.aToken).balanceOf(address(morpho));
            assertApproxEqAbs(morphoBalance, test.supplied, 1, "morphoBalance != supplied");

            assertEq(
                balanceBefore - user1.balanceOf(test.market.underlying),
                amount,
                "balanceBefore - balanceAfter != amount"
            );

            test.morphoMarket = morpho.market(test.market.underlying);
            assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
            assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
            assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
            assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
        }
    }

    function testShouldSupplyP2POnly(uint256 amount, address onBehalf) public returns (SupplyTest memory test) {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            test.market = borrowableMarkets[marketIndex];

            amount = _boundSupply(test.market, amount);
            amount = _promoteSupply(test.market, amount); // 100% peer-to-peer.

            uint256 balanceBefore = user1.balanceOf(test.market.underlying);
            uint256 morphoBalanceBefore = ERC20(test.market.aToken).balanceOf(address(morpho));

            user1.approve(test.market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.BorrowPositionUpdated(address(promoter), test.market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(test.market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user1), onBehalf, test.market.underlying, 0, 0, 0);

            test.supplied = user1.supply(test.market.underlying, amount, onBehalf);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(test.market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(test.market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(test.market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(test.market.underlying, onBehalf);
            uint256 p2pSupply = test.scaledP2PSupply.rayMul(indexes.supply.p2pIndex);

            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertEq(test.supplied, amount, "supplied != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(p2pSupply, amount, 1, "p2pSupply != amount");

            assertEq(morpho.supplyBalance(test.market.underlying, onBehalf), p2pSupply, "totalSupply != p2pSupply");
            assertEq(morpho.collateralBalance(test.market.underlying, onBehalf), 0, "collateral != 0");

            uint256 morphoBalanceAfter = ERC20(test.market.aToken).balanceOf(address(morpho));
            assertApproxEqAbs(morphoBalanceAfter, morphoBalanceBefore, 2, "morphoBalanceAfter != morphoBalanceBefore");
            assertGe(morphoBalanceAfter, morphoBalanceBefore, "morphoBalanceAfter < morphoBalanceBefore");

            assertEq(
                balanceBefore - user1.balanceOf(test.market.underlying),
                amount,
                "balanceBefore - balanceAfter != amount"
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

    function testShouldUpdateIndexesAfterSupply(uint256 amount, address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            user1.supply(market.underlying, amount, onBehalf); // 100% pool.

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

    // TODO: add borrow delta match test

    function testShouldRevertSupplyZero(address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertSupplyOnBehalfZero(uint256 amount) public {
        amount = _boundAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supply(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supply(sAvax, amount, onBehalf);
    }

    function testShouldRevertSupplyWhenSupplyPaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user1.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertSupplyNotEnoughAllowance(uint256 allowance, uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);
            allowance = bound(allowance, 1, amount - 1);

            user1.approve(market.underlying, allowance);

            vm.expectRevert(); // Cannot specify the revert reason as it depends on the ERC20 implementation.
            user1.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldSupplyWhenEverythingElsePaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        morpho.setIsPausedForAllMarkets(true);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            morpho.setIsSupplyPaused(market.underlying, false);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount, onBehalf);
        }
    }
}
