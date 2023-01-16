// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestWithdrawCollateral is IntegrationTest {
    function testShouldWithdrawAllCollateral(uint256 amount, uint256 input) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount);

            input = bound(input, amount + 1, type(uint256).max);

            uint256 withdrawn = user1.withdrawCollateral(market.underlying, input);

            uint256 p2pSupply = morpho.scaledP2PSupplyBalance(market.underlying, address(user1));
            uint256 poolSupply = morpho.scaledPoolSupplyBalance(market.underlying, address(user1));

            assertEq(p2pSupply, 0, "p2pSupply != 0");
            assertEq(poolSupply, 0, "poolSupply != 0");
            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 2, "withdrawn != amount");
        }
    }

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

    function testShouldWithdrawCollateralWhenWithdrawPaused() public {
        uint256 amount = 100;

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            user1.approve(market.underlying, amount);
            user1.supplyCollateral(market.underlying, amount);

            morpho.setIsWithdrawPaused(market.underlying, true);

            user1.withdrawCollateral(market.underlying, amount);
        }
    }
}
