// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestBorrow is IntegrationTest {
    using WadRayMath for uint256;

    // function testShouldBorrow(address managed) public {
    //     vm.assume(managed != address(0));

    //     if (managed != address(user1)) {
    //         vm.prank(managed);
    //         morpho.approveManager(address(user1), true);
    //     }

    //     for (uint256 supplyMarketIndex; supplyMarketIndex < markets.length; ++supplyMarketIndex) {
    //         TestMarket memory supplyMarket = markets[supplyMarketIndex];

    //         for (uint256 borrowMarketIndex; borrowMarketIndex < borrowableMarkets.length; ++borrowMarketIndex) {
    //             _revert();

    //             TestMarket memory borrowMarket = borrowableMarkets[borrowMarketIndex];

    //             user1.borrow(borrowMarket.underlying, 10 ** borrowMarket.decimals, managed);

    //             Types.Indexes256 memory indexes = morpho.updatedIndexes(borrowMarket.underlying);

    //             assertEq(
    //                 morpho.scaledPoolBorrowBalance(borrowMarket.underlying, address(user1)).rayMul(
    //                     indexes.borrow.poolIndex
    //                 )
    //                     + morpho.scaledP2PBorrowBalance(borrowMarket.underlying, address(user1)).rayMul(
    //                         indexes.borrow.p2pIndex
    //                     ),
    //                 amount
    //             );
    //         }
    //     }
    // }

    function testShouldRevertBorrowZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertBorrowOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertBorrowToZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, 100, address(user1), address(0));
        }
    }

    function testShouldRevertBorrowWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.borrow(sAvax, 100);
    }

    function testShouldRevertBorrowWhenBorrowPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsBorrowPaused(market.underlying, true);

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user1.borrow(market.underlying, 100);
        }
    }

    function testShouldRevertBorrowWhenNotManaging(address managed) public {
        vm.assume(managed != address(0) && managed != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.borrow(markets[marketIndex].underlying, 100, managed);
        }
    }
}
