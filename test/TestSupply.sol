// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "./helpers/IntegrationTest.sol";

contract TestSupply is IntegrationTest {
    function testShouldRevertWithZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supply(address(0), 0);
    }
}
