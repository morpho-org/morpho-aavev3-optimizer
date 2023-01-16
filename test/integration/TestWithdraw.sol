// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestWithdraw is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldWithdrawPoolOnly(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            (uint256 supplied,) = _borrowUpTo(market, market, amount, 50_00);

            user1.approve(market.underlying, supplied);
            user1.supply(market.underlying, supplied); // >= 50% pool.

            uint256 balanceBeforeWithdraw = user1.balanceOf(market.underlying);

            amount = supplied / 2;
            uint256 withdrawn = user1.withdraw(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pSupply =
                morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex);
            uint256 poolSupply =
                morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex);
            uint256 totalSupply = poolSupply + p2pSupply;

            assertGe(poolSupply, 0, "poolSupply == 0");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertEq(withdrawn, amount, "withdrawn != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(totalSupply, amount, 2, "supply != amount");

            assertEq(
                user1.balanceOf(market.underlying) - balanceBeforeWithdraw,
                amount,
                "balanceAfter - balanceBeforeWithdraw != amount"
            );
        }
    }

    function testShouldWithdrawAllSupply(uint256 amount, uint256 input) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            (amount,) = _borrowUpTo(market, market, amount, 50_00);

            uint256 balanceBeforeSupply = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount); // >= 50% pool.

            uint256 balanceBeforeWithdraw = user1.balanceOf(market.underlying);

            input = bound(input, amount + 1, type(uint256).max);
            uint256 withdrawn = user1.withdraw(market.underlying, input);

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
            assertApproxEqAbs(
                balanceAfter,
                balanceBeforeSupply,
                10 ** (market.decimals / 2), // TODO: is it ok to lose up to 1e9?
                "balanceAfter != balanceBeforeSupply"
            );
            assertEq(
                balanceAfter - balanceBeforeWithdraw, withdrawn, "balanceAfter - balanceBeforeWithdraw != withdrawn"
            );
        }
    }

    // TODO: add delta tests

    function _prepare(uint256 amount, address onBehalf) internal {
        vm.assume(amount > 0);
        vm.assume(onBehalf != address(0) && onBehalf != address(this)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target

        if (onBehalf != address(user1)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user1), true);
        }
    }

    function testShouldRevertWithdrawZero(address onBehalf) public {
        _prepare(1, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithdrawOnBehalfZero(uint256 amount) public {
        vm.assume(amount > 0);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertWithdrawToZero(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdraw(sAvax, amount, onBehalf);
    }

    function testShouldRevertWithdrawWhenWithdrawPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawIsPaused.selector);
            user1.withdraw(market.underlying, 100);
        }
    }

    function testShouldRevertWithdrawWhenNotManaging(uint256 amount, address onBehalf) public {
        vm.assume(amount > 0);
        vm.assume(onBehalf != address(0) && onBehalf != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdraw(markets[marketIndex].underlying, 100, onBehalf);
        }
    }

    function testShouldWithdrawWhenWithdrawCollateralPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

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
