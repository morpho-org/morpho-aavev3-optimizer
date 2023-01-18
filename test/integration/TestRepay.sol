// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRepay is IntegrationTest {
    function _assumeAmount(uint256 amount) internal pure {
        vm.assume(amount > 0);
    }

    function _assumeOnBehalf(address onBehalf) internal pure {
        vm.assume(onBehalf != address(0));
    }

    function testShouldRevertRepayZero(address onBehalf) public {
        _assumeOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.repay(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertRepayOnBehalfZero(uint256 amount) public {
        _assumeAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.repay(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertRepayWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.repay(sAvax, amount, onBehalf);
    }

    function testShouldRevertRepayWhenRepayPaused(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsRepayPaused(market.underlying, true);

            vm.expectRevert(Errors.RepayIsPaused.selector);
            user1.repay(market.underlying, amount, onBehalf);
        }
    }
}
