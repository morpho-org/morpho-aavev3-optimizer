// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdraw is IntegrationTest {
    using WadRayMath for uint256;

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

    function testShouldWithdrawPoolOnly(uint256 amount, address onBehalf, address receiver) public {
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            (uint256 supplied,) = _borrowUpTo(market, market, amount, 50_00);
            amount = supplied / 2;

            user1.approve(market.underlying, supplied);
            user1.supply(market.underlying, supplied, onBehalf); // >= 50% pool.

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

            assertGe(poolSupply, 0, "poolSupply == 0");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertEq(withdrawn, amount, "withdrawn != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(totalSupply, amount, 2, "supply != amount");

            assertEq(
                ERC20(market.underlying).balanceOf(receiver) - balanceBeforeWithdraw,
                amount,
                "balanceAfter - balanceBeforeWithdraw != amount"
            );
        }
    }

    function testShouldWithdrawAllSupply(uint256 amount, uint256 input, address onBehalf, address receiver) public {
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            (amount,) = _borrowUpTo(market, market, amount, 50_00);
            input = bound(input, amount + 1, type(uint256).max);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount, onBehalf); // >= 50% pool.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.PositionUpdated(true, address(promoter), market.underlying, 0, 0);

            vm.expectEmit(true, false, false, true, address(morpho));
            emit Events.P2PAmountsUpdated(market.underlying, 0, 0);

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

            (amount,) = _borrowUpTo(market, market, amount, 50_00);

            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount); // >= 50% pool.

            user1.withdraw(market.underlying, type(uint256).max);

            uint256 balanceAfter = user1.balanceOf(market.underlying);
            assertLe(balanceAfter, balanceBefore, "balanceAfter > balanceBefore");
            assertApproxEqAbs(balanceAfter, balanceBefore, 1, "balanceAfter != balanceBefore");
        }
    }

    function testShouldNotWithdrawWhenNoSupply(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

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

    // TODO: add delta tests

    function testShouldRevertWithdrawZero(address onBehalf, address receiver) public {
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawOnBehalfZero(uint256 amount, address receiver) public {
        _assumeAmount(amount);
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertWithdrawToZero(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdraw(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawWhenWithdrawPaused(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

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
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldWithdrawWhenWithdrawCollateralPaused(uint256 amount, address onBehalf, address receiver)
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
            user1.supply(market.underlying, amount);

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            user1.withdraw(market.underlying, amount);
        }
    }
}
