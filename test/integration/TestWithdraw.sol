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

    function testShouldWithdrawPoolOnly(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            uint256 supplied = _boundSupply(market, amount);
            uint256 promoted = _promoteSupply(market, supplied.percentMul(50_00)); // 50% peer-to-peer.
            amount = supplied - promoted;

            user1.approve(market.underlying, supplied);
            user1.supply(market.underlying, supplied, onBehalf); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.

            uint256 balanceBeforeWithdraw = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(onBehalf, receiver, market.underlying, 0, 0, 0);

            uint256 withdrawn = user1.withdraw(market.underlying, amount, onBehalf, receiver);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pSupply =
                morpho.scaledP2PSupplyBalance(market.underlying, onBehalf).rayMul(indexes.supply.p2pIndex);
            uint256 poolSupply =
                morpho.scaledPoolSupplyBalance(market.underlying, onBehalf).rayMul(indexes.supply.poolIndex);
            uint256 totalSupply = poolSupply + p2pSupply;

            if (promoted == 0) {
                assertEq(poolSupply, 0, "poolSupply != 0");
            } else {
                assertGe(poolSupply, 0, "poolSupply == 0");
                assertLe(poolSupply, supplied - withdrawn, "poolSupply > supplied - withdrawn");
            }

            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 1, "withdrawn != amount");
            assertLe(p2pSupply, promoted, "p2pSupply > promoted");
            assertApproxEqAbs(p2pSupply, promoted, 2, "p2pSupply != promoted");

            assertEq(
                morpho.supplyBalance(market.underlying, onBehalf), totalSupply, "totalSupply != poolSupply + p2pSupply"
            );

            assertApproxEqAbs(
                ERC20(market.underlying).balanceOf(receiver) - balanceBeforeWithdraw,
                amount,
                1,
                "balanceAfter - balanceBeforeWithdraw != amount"
            );
        }
    }

    function testShouldWithdrawAllSupply(uint256 amount, uint256 input, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);
            input = bound(input, amount + 1, type(uint256).max);
            _promoteSupply(market, amount.percentMul(50_00)); // 50% peer-to-peer.

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount, onBehalf); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            // vm.expectEmit(true, true, true, false, address(morpho));
            // emit Events.PositionUpdated(true, address(promoter), market.underlying, 0, 0);

            // vm.expectEmit(true, false, false, false, address(morpho));
            // emit Events.P2PAmountsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Withdrawn(onBehalf, receiver, market.underlying, 0, 0, 0);

            uint256 withdrawn = user1.withdraw(market.underlying, input, onBehalf, receiver);

            uint256 p2pSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            uint256 poolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
            uint256 collateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);

            assertEq(p2pSupply, 0, "p2pSupply != 0");
            assertEq(poolSupply, 0, "poolSupply != 0");
            assertEq(collateral, 0, "collateral != 0");
            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 2, "withdrawn != amount");

            assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "totalSupply != 0");

            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                withdrawn,
                "balanceAfter - balanceBefore != withdrawn"
            );
        }
    }

    function testShouldNotWithdrawMoreThanSupply(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);
            _promoteSupply(market, amount.percentMul(50_00)); // 50% peer-to-peer.

            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.

            user1.withdraw(market.underlying, type(uint256).max);

            uint256 balanceAfter = user1.balanceOf(market.underlying);
            assertLe(balanceAfter, balanceBefore, "balanceAfter > balanceBefore");
            assertApproxEqAbs(balanceAfter, balanceBefore, 1, "balanceAfter != balanceBefore");
        }
    }

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

            vm.expectEmit(true, false, false, false, address(morpho));
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

    function testShouldWithdrawWhenWithdrawCollateralPaused(uint256 amount, address onBehalf, address receiver)
        public
    {
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

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            user1.withdraw(market.underlying, amount);
        }
    }
}
