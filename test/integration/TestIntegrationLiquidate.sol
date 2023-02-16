// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

import "@forge-std/StdStorage.sol";

contract TestIntegrationLiquidate is IntegrationTest {
    using WadRayMath for uint256;
    using stdStorage for StdStorage;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    uint256 internal constant MIN_AMOUNT = 10_000_000;
    uint256 internal constant MIN_PRICE_AMOUNT = 100_000_000; // 10$
    uint256 internal constant MAX_AMOUNT = 100 ether;

    function testShouldNotLiquidateHealthyUser(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                uint256 minAmount = MIN_PRICE_AMOUNT * (10 ** borrowedMarket.decimals) / borrowedMarket.price;
                amount = bound(amount, minAmount, MAX_AMOUNT);

                (, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                toRepay = bound(toRepay, minAmount, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                vm.expectRevert(Errors.UnauthorizedLiquidate.selector);
                user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);
            }
        }
    }

    function testShouldNotLiquidateUserNotOnCollateralMarket(address borrower, uint256 amount, uint256 toRepay)
        public
    {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (uint256 supplied, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                assertGt(supplied, 0);
                assertGt(borrowed, 0);

                stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
                    collateralMarket.underlying
                ).with_key(borrower).checked_write(
                    morpho.scaledCollateralBalance(collateralMarket.underlying, borrower) / 2
                );

                toRepay = bound(toRepay, MIN_AMOUNT, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                address collateralUnderlying =
                    collateralUnderlyings[collateralIndex + 1 == collateralUnderlyings.length ? 0 : collateralIndex + 1];

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedMarket.underlying, collateralUnderlying, borrower, toRepay);

                assertEq(repaid, 0);
                assertEq(seized, 0);
            }
        }
    }

    function testShouldNotLiquidateUserNotInBorrowMarket(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (uint256 supplied, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                assertGt(supplied, 0);
                assertGt(borrowed, 0);

                stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
                    collateralMarket.underlying
                ).with_key(borrower).checked_write(
                    morpho.scaledCollateralBalance(collateralMarket.underlying, borrower) / 2
                );

                toRepay = bound(toRepay, MIN_AMOUNT, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                address borrowedUnderlying =
                    borrowableUnderlyings[borrowedIndex + 1 == borrowableUnderlyings.length ? 0 : borrowedIndex + 1];

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedUnderlying, collateralMarket.underlying, borrower, toRepay);

                assertEq(repaid, 0);
                assertEq(seized, 0);
            }
        }
    }

    function testLiquidateUnhealthyUser(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (uint256 supplied, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
                    collateralMarket.underlying
                ).with_key(borrower).checked_write(
                    morpho.scaledCollateralBalance(collateralMarket.underlying, borrower) / 2
                );

                toRepay = bound(toRepay, MIN_AMOUNT, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.Liquidated(
                    address(user), borrower, borrowedMarket.underlying, 0, collateralMarket.underlying, 0
                    );

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                assertGt(repaid, 0);
                assertGt(seized, 0);
                assertLe(repaid, borrowed);
                assertLe(seized, supplied);
            }
        }
    }

    function testLiquidateUnhealthyUserBorrowMatched(
        address borrower,
        uint256 amount,
        uint256 promoted,
        uint256 toRepay
    ) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (uint256 supplied, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                promoted = bound(0, promoted, borrowed);
                _promoteBorrow(promoter1, borrowedMarket, promoted);

                stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
                    collateralMarket.underlying
                ).with_key(borrower).checked_write(
                    morpho.scaledCollateralBalance(collateralMarket.underlying, borrower) / 2
                );

                toRepay = bound(toRepay, MIN_AMOUNT, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.Liquidated(
                    address(user), borrower, borrowedMarket.underlying, 0, collateralMarket.underlying, 0
                    );

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                assertGt(repaid, 0);
                assertGt(seized, 0);
                assertLe(repaid, borrowed);
                assertLe(seized, supplied);
            }
        }
    }

    function testShouldLiquidateAnyUserOnDeprecatedMarket(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (uint256 supplied, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                morpho.setIsBorrowPaused(borrowedMarket.underlying, true);
                morpho.setIsDeprecated(borrowedMarket.underlying, true);

                toRepay = bound(toRepay, MIN_AMOUNT, borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.Liquidated(
                    address(user), borrower, borrowedMarket.underlying, 0, collateralMarket.underlying, 0
                    );

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                assertGt(repaid, 0);
                assertGt(seized, 0);
                assertLe(repaid, borrowed);
                assertLe(seized, supplied);
            }
        }
    }

    function testShouldRevertWhenCollateralMarketNotCreated(address underlying, address borrower, uint256 amount)
        public
    {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.assume(underlying != allUnderlyings[i]);
        }

        for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
            _revert();

            TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

            vm.expectRevert();
            user.liquidate(borrowedMarket.underlying, underlying, borrower, amount);
        }
    }

    function testShouldRevertWhenBorrowMarketNotCreated(address underlying, address borrower, uint256 amount) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.assume(underlying != allUnderlyings[i]);
        }

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            _revert();

            TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];

            vm.expectRevert();
            user.liquidate(underlying, collateralMarket.underlying, borrower, amount);
        }
    }

    function testShouldRevertWhenLiquidateCollateralIsPaused(address borrower, uint256 amount) public {
        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                morpho.setIsLiquidateBorrowPaused(borrowedMarket.underlying, true);

                vm.expectRevert(Errors.LiquidateBorrowIsPaused.selector);
                user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, amount);
            }
        }
    }

    function testShouldRevertWhenLiquidateBorrowIsPaused(address borrower, uint256 amount) public {
        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                morpho.setIsLiquidateCollateralPaused(collateralMarket.underlying, true);

                vm.expectRevert(Errors.LiquidateCollateralIsPaused.selector);
                user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, amount);
            }
        }
    }

    function testShouldRevertWhenBorrowerZero(uint256 amount) public {
        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                vm.expectRevert(Errors.AddressIsZero.selector);
                user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, address(0), amount);
            }
        }
    }

    function _boundAmountWithPrice(uint256 amount, TestMarket memory market) internal view returns (uint256) {
        uint256 minAmount = MIN_PRICE_AMOUNT * (10 ** market.decimals) / market.price;
        return bound(amount, minAmount, MAX_AMOUNT);
    }
}
