// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdrawCollateral is IntegrationTest {
    function _assumeAmount(uint256 amount) internal pure {
        vm.assume(amount > 0);
    }

    function _assumeOnBehalf(address onBehalf) internal view {
        vm.assume(onBehalf != address(0) && onBehalf != address(this)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target
    }

    function _assumeReceiver(address receiver) internal pure {
        vm.assume(receiver != address(0));
    }

    function _prepareOnBehalf(address onBehalf) internal {
        if (onBehalf != address(user1)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user1), true);
        }
    }

    function testShouldWithdrawAllCollateral(uint256 amount, uint256 input, address onBehalf, address receiver)
        public
    {
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);
            input = bound(input, amount + 1, type(uint256).max);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount, onBehalf);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.CollateralWithdrawn(onBehalf, receiver, market.underlying, 0, 0);

            uint256 withdrawn = user1.withdrawCollateral(market.underlying, input, onBehalf, receiver);

            uint256 p2pSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            uint256 poolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
            uint256 collateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);

            assertEq(p2pSupply, 0, "p2pSupply != 0");
            assertEq(poolSupply, 0, "poolSupply != 0");
            assertEq(collateral, 0, "collateral != 0");
            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 2, "withdrawn != amount");

            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBefore,
                withdrawn,
                "balanceAfter - balanceBefore != withdrawn"
            );
        }
    }

    function testShouldNotWithdrawMoreThanCollateral(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount); // >= 50% pool.

            user1.withdrawCollateral(market.underlying, type(uint256).max);

            uint256 balanceAfter = user1.balanceOf(market.underlying);
            assertLe(balanceAfter, balanceBefore, "balanceAfter > balanceBefore");
            assertApproxEqAbs(balanceAfter, balanceBefore, 1, "balanceAfter != balanceBefore");
        }
    }

    function testShouldNotWithdrawWhenNoCollateral(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

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

    function testShouldRevertWithdrawCollateralZero(address onBehalf) public {
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithdrawCollateralOnBehalfZero(uint256 amount) public {
        _assumeAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralToZero(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver)
        public
    {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdrawCollateral(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawCollateralWhenWithdrawCollateralPaused(
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

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
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, amount, onBehalf);
        }
    }

    function testShouldWithdrawCollateralWhenWithdrawPaused(uint256 amount, address onBehalf, address receiver)
        public
    {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

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
