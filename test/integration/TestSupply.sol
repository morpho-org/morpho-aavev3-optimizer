// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupply is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldSupply(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            // Supply should still work if supplyCollateral is paused.
            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            uint256 supplied = user1.supply(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 supplyBalance = morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(
                indexes.supply.poolIndex
            ) + morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex);

            assertEq(supplied, amount);
            assertApproxEqAbs(supplyBalance, amount, 1);
            assertLe(supplyBalance, amount);
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

    function testShouldRevertSupplyWhenSupplyIsPaused() public {
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
}
