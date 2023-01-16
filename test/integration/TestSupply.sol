// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupply is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldSupplyPoolOnly(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            uint256 balanceBefore = user1.balanceOf(market.underlying);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user1), onBehalf, market.underlying, 0, 0, 0);

            uint256 supplied = user1.supply(market.underlying, amount, onBehalf); // 100% pool.

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 poolSupply =
                morpho.scaledPoolSupplyBalance(market.underlying, onBehalf).rayMul(indexes.supply.poolIndex);
            uint256 scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);

            assertEq(scaledP2PSupply, 0, "p2pSupply != 0");
            assertEq(supplied, amount, "supplied != amount");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertApproxEqAbs(poolSupply, amount, 1, "poolSupply != amount");

            uint256 morphoBalance = ERC20(market.aToken).balanceOf(address(morpho));
            assertApproxEqAbs(morphoBalance, supplied, 1, "morphoBalance != supplied");

            assertEq(balanceBefore - user1.balanceOf(market.underlying), amount, "balanceDiff != amount");
        }
    }

    function testShouldSupplyP2POnly(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            uint256 collateral;
            (collateral, amount) = _borrowUpTo(market, market, amount, 100_00);

            uint256 balanceBefore = user1.balanceOf(market.underlying);
            uint256 morphoBalanceBefore = ERC20(market.aToken).balanceOf(address(morpho));

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.PositionUpdated(true, address(promoter), market.underlying, 0, 0);

            vm.expectEmit(true, false, false, false, address(morpho));
            emit Events.P2PAmountsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user1), onBehalf, market.underlying, 0, 0, 0);

            uint256 supplied = user1.supply(market.underlying, amount, onBehalf); // 100% peer-to-peer.

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pSupply =
                morpho.scaledP2PSupplyBalance(market.underlying, onBehalf).rayMul(indexes.supply.p2pIndex);
            uint256 scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);

            assertEq(scaledPoolSupply, 0, "poolSupply != 0");
            assertEq(supplied, amount, "supplied != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(p2pSupply, amount, 1, "p2pSupply != amount");

            assertEq(
                ERC20(market.aToken).balanceOf(address(morpho)),
                morphoBalanceBefore,
                "morphoBalanceAfter != morphoBalanceBefore"
            );

            assertEq(balanceBefore - user1.balanceOf(market.underlying), amount, "balanceDiff != amount");
        }
    }

    // TODO: add delta tests

    function _prepare(uint256 amount, address onBehalf) internal pure {
        vm.assume(amount > 0);
        vm.assume(onBehalf != address(0));
    }

    function testShouldRevertSupplyZero(address onBehalf) public {
        vm.assume(onBehalf != address(0));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertSupplyOnBehalfZero(uint256 amount) public {
        vm.assume(amount > 0);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supply(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supply(sAvax, amount, onBehalf);
    }

    function testShouldRevertSupplyWhenSupplyPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user1.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertSupplyNotEnoughAllowance(uint256 allowance, uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

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

    function testShouldSupplyWhenSupplyCollateralPaused(uint256 amount, address onBehalf) public {
        _prepare(amount, onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount, onBehalf);
        }
    }
}
