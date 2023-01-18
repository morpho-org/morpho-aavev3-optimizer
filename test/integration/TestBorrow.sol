// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;

    function _assumeAmount(uint256 amount) internal pure {
        vm.assume(amount > 0);
    }

    function _assumeOnBehalf(address onBehalf) internal view {
        vm.assume(onBehalf != address(0) && onBehalf != address(this)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target
    }

    function _assumeReceiver(address receiver) internal pure {
        vm.assume(receiver != address(0));
    }

    function _prepareOnBehalf(address onBehalf) internal {
        if (onBehalf != address(user1)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user1), true);
        }
    }

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

    function testShouldRevertBorrowZero(address onBehalf, address receiver) public {
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowOnBehalfZero(uint256 amount, address receiver) public {
        _assumeAmount(amount);
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertBorrowToZero(uint256 amount, address onBehalf) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.borrow(markets[marketIndex].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertBorrowWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.borrow(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertBorrowWhenBorrowPaused(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        _assumeReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsBorrowPaused(market.underlying, true);

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user1.borrow(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        _assumeAmount(amount);
        _assumeOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));
        _assumeReceiver(receiver);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.borrow(markets[marketIndex].underlying, amount, onBehalf, receiver);
        }
    }
}
