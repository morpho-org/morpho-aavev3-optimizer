// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSupply is IntegrationTest {
    using WadRayMath for uint256;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        return address(uint160(bound(uint256(uint160(onBehalf)), 1, type(uint160).max)));
    }

    function testShouldRevertSupplyZero(address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.supply(testMarkets[markets[marketIndex]].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.supply(sAvax, amount, onBehalf);
    }
}
