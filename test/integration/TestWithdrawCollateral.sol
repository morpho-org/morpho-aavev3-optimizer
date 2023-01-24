// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdrawCollateral is IntegrationTest {
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

    struct WithdrawCollateralTest {
        uint256 supplied;
        uint256 withdrawn;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        TestMarket market;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldWithdrawAllCollateral(uint256 amount, address onBehalf, address receiver)
        public
        returns (WithdrawCollateralTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            test.market = markets[marketIndex];

            test.supplied = _boundSupply(test.market, amount);
            amount = bound(amount, test.supplied + 1, type(uint256).max);

            user1.approve(test.market.underlying, test.supplied);
            user1.supplyCollateral(test.market.underlying, test.supplied, onBehalf);

            uint256 balanceBefore = ERC20(test.market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.CollateralWithdrawn(
                address(user1), onBehalf, receiver, test.market.underlying, test.supplied, 0
                );

            test.withdrawn = user1.withdrawCollateral(test.market.underlying, amount, onBehalf, receiver);

            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(test.market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(test.market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(test.market.underlying, onBehalf);

            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertLe(test.withdrawn, test.supplied, "withdrawn > supplied");
            assertApproxEqAbs(test.withdrawn, test.supplied, 2, "withdrawn != supplied");

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

    function testShouldNotWithdrawWhenNoCollateral(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            uint256 withdrawn = user1.withdrawCollateral(market.underlying, amount, onBehalf, receiver);

            uint256 balanceAfter = ERC20(market.underlying).balanceOf(receiver);

            assertEq(withdrawn, 0, "withdrawn != 0");
            assertEq(balanceAfter, balanceBefore, "balanceAfter != balanceBefore");
        }
    }

    function testShouldRevertWithdrawCollateralZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawCollateralOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertWithdrawCollateralToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver)
        public
    {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdrawCollateral(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawCollateralWhenWithdrawCollateralPaused(
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawCollateralIsPaused.selector);
            user1.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertWithdrawCollateralWhenNotManaging(uint256 amount, address onBehalf, address receiver)
        public
    {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf);
        }
    }

    function testShouldWithdrawCollateralWhenEverythingElsePaused(uint256 amount, address onBehalf, address receiver)
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
            user1.supplyCollateral(market.underlying, amount);

            morpho.setIsPausedForAllMarkets(true);
            morpho.setIsWithdrawCollateralPaused(market.underlying, false);

            user1.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }
}
