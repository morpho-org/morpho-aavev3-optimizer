// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupplyCollateral is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldSupplyCollateral(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            uint256 supplied = user1.supplyCollateral(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 collateral =
                morpho.scaledCollateralBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex); // TODO: rayMulDown?

            assertEq(supplied, amount, "supplied != amount");
            assertLe(collateral, amount, "collateral > amount"); // TODO: assertEq?
            assertApproxEqAbs(collateral, amount, 1, "collateral != amount");
        }
    }

    function testShouldRevertSupplyCollateralZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supplyCollateral(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertSupplyCollateralOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supplyCollateral(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertSupplyCollateralWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supplyCollateral(sAvax, 100);
    }

    function testShouldRevertSupplyCollateralWhenSupplyCollateralPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyCollateralIsPaused.selector);
            user1.supplyCollateral(market.underlying, 100);
        }
    }

    function testShouldSupplyCollateralWhenSupplyPaused() public {
        uint256 amount = 100;

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyPaused(market.underlying, true);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount);
        }
    }
}
