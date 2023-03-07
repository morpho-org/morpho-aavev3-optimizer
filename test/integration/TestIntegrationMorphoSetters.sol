// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMorphoSetters is IntegrationTest {
    using WadRayMath for uint256;

    function testSetIsClaimRewardsPausedRevertIfCallerNotOwner(address caller, bool isPaused) public {
        vm.assume(caller != address(this));

        vm.startPrank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsClaimRewardsPaused(isPaused);
    }

    function testSetIsClaimRewardsPaused(bool isPaused) public {
        vm.expectEmit(true, true, true, true, address(morpho));
        emit Events.IsClaimRewardsPausedSet(isPaused);

        morpho.setIsClaimRewardsPaused(isPaused);
        assertEq(morpho.isClaimRewardsPaused(), isPaused);
    }

    function testShouldSetBorrowPaused() public {
        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);

            assertEq(morpho.market(market.underlying).pauseStatuses.isBorrowPaused, true);
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

            assertEq(morpho.market(market.underlying).pauseStatuses.isDeprecated, isDeprecated);
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
