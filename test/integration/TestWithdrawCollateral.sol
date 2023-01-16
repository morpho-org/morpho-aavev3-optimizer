// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestWithdrawCollateral is IntegrationTest {
    function testShouldWithdrawAllCollateral(uint256 amount, uint256 input) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            uint256 balanceBeforeSupply = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount);

            uint256 balanceBeforeWithdraw = user1.balanceOf(market.underlying);

            input = bound(input, amount + 1, type(uint256).max);
            uint256 withdrawn = user1.withdrawCollateral(market.underlying, input);

            uint256 p2pSupply = morpho.scaledP2PSupplyBalance(market.underlying, address(user1));
            uint256 poolSupply = morpho.scaledPoolSupplyBalance(market.underlying, address(user1));
            uint256 collateral = morpho.scaledCollateralBalance(market.underlying, address(user1));

            assertEq(p2pSupply, 0, "p2pSupply != 0");
            assertEq(poolSupply, 0, "poolSupply != 0");
            assertEq(collateral, 0, "collateral != 0");
            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 2, "withdrawn != amount");

            uint256 balanceAfter = user1.balanceOf(market.underlying);
            assertLe(balanceAfter, balanceBeforeSupply, "balanceAfter > balanceBeforeSupply");
            assertApproxEqAbs(balanceAfter, balanceBeforeSupply, 2, "balanceAfter != balanceBeforeSupply");
            assertEq(
                balanceAfter - balanceBeforeWithdraw, withdrawn, "balanceAfter - balanceBeforeWithdraw != withdrawn"
            );
        }
    }

    function _prepare(uint256 amount, address onBehalf) internal {
        vm.assume(amount > 0);
        vm.assume(onBehalf != address(0) && onBehalf != address(this)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target

        if (onBehalf != address(user1)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user1), true);
        }
    }

    function testShouldRevertWithdrawCollateralZero(address onBehalf) public {
        _prepare(1, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithdrawCollateralOnBehalfZero(uint256 amount) public {
        vm.assume(amount > 0);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralToZero(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdrawCollateral(sAvax, amount, onBehalf);
    }

    function testShouldRevertWithdrawCollateralWhenWithdrawCollateralPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawCollateralIsPaused.selector);
            user1.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertWithdrawCollateralWhenNotManaging(uint256 amount, address onBehalf) public {
        vm.assume(amount > 0);
        vm.assume(onBehalf != address(0) && onBehalf != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf);
        }
    }

    function testShouldWithdrawCollateralWhenWithdrawPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount);

            morpho.setIsWithdrawPaused(market.underlying, true);

            user1.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }
}
