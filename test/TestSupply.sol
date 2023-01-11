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

    /// @dev The index calculation reverts if the market has no initialized indexes due to division by 0, so no revert reason should be given.
    function testShouldRevertWithMarketNotCreated() public {
        vm.expectRevert();
        user1.supply(sAvax, 100);
    }
}
