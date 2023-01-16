// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestBorrow is IntegrationTest {
    using WadRayMath for uint256;

    // function testShouldBorrowPoolOnly(address managed, uint256 amount) public {
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

    //             uint256 collateral = _boundSupply(supplyMarket, amount);
    //             amount = _boundBorrow(supplyMarket, borrowMarket, collateral);

    //             user1.approve(supplyMarket.underlying, collateral);
    //             user1.supplyCollateral(supplyMarket.underlying, collateral);
    //             uint256 borrowed = user1.borrow(borrowMarket.underlying, amount, managed);

    //             Types.Indexes256 memory indexes = morpho.updatedIndexes(borrowMarket.underlying);
    //             uint256 poolBorrow = morpho.scaledPoolBorrowBalance(borrowMarket.underlying, address(user1)).rayMul(
    //                 indexes.borrow.poolIndex
    //             );
    //             uint256 scaledP2PBorrow = morpho.scaledP2PBorrowBalance(borrowMarket.underlying, address(user1));

    //             assertEq(ERC20(borrowMarket.underlying).balanceOf(address(user1)), borrowed, "balanceOf != borrowed");

    //             assertEq(scaledP2PBorrow, 0, "p2pBorrow != 0");
    //             assertEq(borrowed, amount, "borrowed != amount");
    //             assertLe(poolBorrow, amount, "poolBorrow > amount");
    //             assertApproxEqAbs(poolBorrow, amount, 1, "poolBorrow != amount");
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
