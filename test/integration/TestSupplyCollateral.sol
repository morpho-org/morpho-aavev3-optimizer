// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupplyCollateral is IntegrationTest {
    using WadRayMath for uint256;

    // function testShouldSupplyCollateral(uint256 amount) public {
    //     for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
    //         _revert();

    //         TestMarket memory market = markets[marketIndex];

    //         // TODO: pause supply (thus we check if supplyCollateral still works)

    //         amount = _boundSupply(market, amount);

    //         user1.approve(market.underlying, amount);
    //         user1.supply(market.underlying, amount);

    //         Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);

    //         assertEq(
    //             morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex)
    //                 + morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex),
    //             amount
    //         );
    //     }
    // }

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

    function testShouldRevertSupplyCollateralWhenSupplyCollateralIsPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyCollateralIsPaused.selector);
            user1.supplyCollateral(market.underlying, 100);
        }
    }
}
