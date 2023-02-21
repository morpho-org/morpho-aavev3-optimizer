// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSetters is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldSetBorrowPaused() public {
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);
        }
    }

    function testShouldNotSetBorrowNotPausedWhenDeprecated() public {
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);
            morpho.setIsDeprecated(market.underlying, true);

            vm.expectRevert(Errors.MarketIsDeprecated.selector);
            morpho.setIsBorrowPaused(market.underlying, false);
        }
    }

    function testShouldSetDeprecatedWhenBorrowPaused(bool isDeprecated) public {
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);

            morpho.setIsDeprecated(market.underlying, isDeprecated);
        }
    }

    function testShouldNotSetDeprecatedWhenBorrowNotPaused(bool isDeprecated) public {
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, false);

            vm.expectRevert(Errors.BorrowNotPaused.selector);
            morpho.setIsDeprecated(market.underlying, isDeprecated);
        }
    }
}
