// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupply is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function testShouldSupplyPoolOnly(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            uint256 supplied = user1.supply(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 poolSupply =
                morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex);

            assertEq(supplied, amount, "supplied != amount");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertApproxEqAbs(poolSupply, amount, 1, "poolSupply != amount");
        }
    }

    function testShouldSupplyP2POnly(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            uint256 collateral = _boundSupply(market, amount);
            amount = _boundBorrow(market, collateral);

            user2.approve(market.underlying, collateral);
            user2.supplyCollateral(market.underlying, collateral);
            user2.borrow(market.underlying, amount);

            _forward(1);

            user1.approve(market.underlying, amount);
            uint256 supplied = user1.supply(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pSupply =
                morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex);

            assertEq(supplied, amount, "supplied != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(p2pSupply, amount, 1, "p2pSupply != amount");
        }
    }

    function testShouldRevertSupplyZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertSupplyOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supply(sAvax, 100);
    }

    function testShouldRevertSupplyWhenSupplyPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user1.supply(market.underlying, 100);
        }
    }

    function testShouldRevertSupplyNotEnoughAllowance(uint256 allowance, uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);
            allowance = bound(allowance, 1, amount - 1);

            user1.approve(market.underlying, allowance);

            vm.expectRevert();
            user1.supply(market.underlying, amount);
        }
    }

    function testShouldSupplyWhenSupplyCollateralPaused() public {
        uint256 amount = 100;

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount);
        }
    }
}
