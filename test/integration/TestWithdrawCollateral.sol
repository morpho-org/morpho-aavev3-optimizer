// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestWithdrawCollateral is IntegrationTest {
    function testShouldRevertWithdrawCollateralZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithdrawCollateralOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralToZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 100, address(user1), address(0));
        }
    }

    function testShouldRevertWithdrawCollateralWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdrawCollateral(sAvax, 100);
    }

    function testShouldRevertWithdrawCollateralWhenWithdrawCollateralPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawCollateralIsPaused.selector);
            user1.withdrawCollateral(market.underlying, 100);
        }
    }

    function testShouldRevertWithdrawCollateralWhenNotManaging(address managed) public {
        vm.assume(managed != address(0) && managed != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdrawCollateral(markets[marketIndex].underlying, 100, managed);
        }
    }
}
