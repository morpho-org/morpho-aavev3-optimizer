// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSupplyCollateral is IntegrationTest {
    using WadRayMath for uint256;

    function _assumeAmount(uint256 amount) internal pure {
        vm.assume(amount > 0);
    }

    function _assumeOnBehalf(address onBehalf) internal pure {
        vm.assume(onBehalf != address(0));
    }

    function testShouldSupplyCollateral(uint256 amount, address onBehalf) public {
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.CollateralSupplied(address(user1), onBehalf, market.underlying, 0, 0);

            uint256 supplied = user1.supplyCollateral(market.underlying, amount, onBehalf);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 collateral =
                morpho.scaledCollateralBalance(market.underlying, onBehalf).rayMul(indexes.supply.poolIndex); // TODO: rayMulDown?

            assertEq(supplied, amount, "supplied != amount");
            assertLe(collateral, amount, "collateral > amount"); // TODO: assertEq?
            assertApproxEqAbs(collateral, amount, 1, "collateral != amount");
        }
    }

    function testShouldRevertSupplyCollateralZero(address onBehalf) public {
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supplyCollateral(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertSupplyCollateralOnBehalfZero(uint256 amount) public {
        _assumeAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supplyCollateral(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertSupplyCollateralWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supplyCollateral(sAvax, amount, onBehalf);
    }

    function testShouldRevertSupplyCollateralWhenSupplyCollateralPaused(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyCollateralIsPaused.selector);
            user1.supplyCollateral(market.underlying, amount, onBehalf);
        }
    }

    function testShouldSupplyCollateralWhenSupplyPaused(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            morpho.setIsSupplyPaused(market.underlying, true);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount, onBehalf);
        }
    }
}
