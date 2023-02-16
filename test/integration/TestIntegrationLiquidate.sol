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

    struct LiquidateTest {
        uint256 supplied;
        uint256 borrowed;
        uint256 repaid;
        uint256 seized;
    }

    function testShouldNotLiquidateHealthyUser(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, borrowed), borrowed);

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

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, borrowed), borrowed);

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

                _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, borrowed), borrowed);

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

                (, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                (uint256 borrowBalance, uint256 collateralBalance) =
                    _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, borrowed), borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                _assertEvents(address(user), borrower, collateralMarket, borrowedMarket);

                (uint256 repaid, uint256 seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                _assertLiquidation(
                    borrowedMarket,
                    collateralMarket,
                    borrower,
                    toRepay,
                    borrowBalance,
                    collateralBalance,
                    repaid,
                    seized
                );
            }
        }
    }

    function testLiquidateUnhealthyUserWhenBorrowPartiallyMatched(
        address borrower,
        uint256 amount,
        uint256 promoted,
        uint256 toRepay
    ) public {
        vm.assume(borrower != address(0));

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                promoted = bound(promoted, 0, test.borrowed);
                _promoteBorrow(promoter1, borrowedMarket, promoted);

                (uint256 borrowBalance, uint256 collateralBalance) =
                    _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                _assertEvents(address(user), borrower, collateralMarket, borrowedMarket);

                (test.repaid, test.seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                _assertLiquidation(
                    borrowedMarket,
                    collateralMarket,
                    borrower,
                    toRepay,
                    borrowBalance,
                    collateralBalance,
                    test.repaid,
                    test.seized
                );
            }
        }
    }

    function testLiquidateUnhealthyUserWhenSupplyCapExceeded(
        address borrower,
        uint256 amount,
        uint256 toRepay,
        uint256 supplyCap
    ) public {
        vm.assume(borrower != address(0));

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                _promoteBorrow(promoter1, borrowedMarket, test.borrowed); // 100% peer-to-peer.

                supplyCap = _boundSupplyCapExceeded(borrowedMarket, test.borrowed, supplyCap);
                _setSupplyCap(borrowedMarket, supplyCap);

                (uint256 borrowBalance, uint256 collateralBalance) =
                    _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                _assertEvents(address(user), borrower, collateralMarket, borrowedMarket);

                (test.repaid, test.seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                _assertLiquidation(
                    borrowedMarket,
                    collateralMarket,
                    borrower,
                    toRepay,
                    borrowBalance,
                    collateralBalance,
                    test.repaid,
                    test.seized
                );
            }
        }
    }

    function testLiquidateUnhealthyUserWhenDemotedZero(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                _promoteBorrow(promoter1, borrowedMarket, test.borrowed); // 100% peer-to-peer.

                // Set the max iterations to 0 upon repay to skip demotion and fallback to supply delta.
                morpho.setDefaultIterations(Types.Iterations({repay: 0, withdraw: 10}));

                (uint256 borrowBalance, uint256 collateralBalance) =
                    _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                _assertEvents(address(user), borrower, collateralMarket, borrowedMarket);

                (test.repaid, test.seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                _assertLiquidation(
                    borrowedMarket,
                    collateralMarket,
                    borrower,
                    toRepay,
                    borrowBalance,
                    collateralBalance,
                    test.repaid,
                    test.seized
                );
            }
        }
    }

    function testLiquidateAnyUserOnDeprecatedMarket(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                uint256 borrowBalance = morpho.borrowBalance(borrowedMarket.underlying, borrower);
                uint256 collateralBalance = morpho.collateralBalance(collateralMarket.underlying, borrower);

                morpho.setIsBorrowPaused(borrowedMarket.underlying, true);
                morpho.setIsDeprecated(borrowedMarket.underlying, true);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                _assertEvents(address(user), borrower, collateralMarket, borrowedMarket);

                (test.repaid, test.seized) =
                    user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);

                _assertLiquidation(
                    borrowedMarket,
                    collateralMarket,
                    borrower,
                    toRepay,
                    borrowBalance,
                    collateralBalance,
                    test.repaid,
                    test.seized
                );
            }
        }
    }

    function testShouldUpdateIndexesAfterLiquidate(address borrower, uint256 amount, uint256 toRepay) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundAmountWithPrice(amount, borrowedMarket);

                (, uint256 borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );
                vm.warp(block.timestamp + 1);

                _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, borrowed), borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                vm.expectEmit(true, true, true, false, address(morpho));
                emit Events.IndexesUpdated(borrowedMarket.underlying, 0, 0, 0, 0);

                if (borrowedMarket.underlying != collateralMarket.underlying) {
                    vm.expectEmit(true, true, true, false, address(morpho));
                    emit Events.IndexesUpdated(collateralMarket.underlying, 0, 0, 0, 0);
                }

                user.liquidate(borrowedMarket.underlying, collateralMarket.underlying, borrower, toRepay);
            }
        }
    }

    function testShouldRevertWhenCollateralMarketNotCreated(address underlying, address borrower, uint256 amount)
        public
    {
        _assumeNotPartOfAllUnderlyings(underlying);

        for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
            _revert();

            TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

            vm.expectRevert();
            user.liquidate(borrowedMarket.underlying, underlying, borrower, amount);
        }
    }

    function testShouldRevertWhenBorrowMarketNotCreated(address underlying, address borrower, uint256 amount) public {
        _assumeNotPartOfAllUnderlyings(underlying);

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

    function _assertLiquidation(
        TestMarket storage borrowedMarket,
        TestMarket storage collateralMarket,
        address borrower,
        uint256 toRepay,
        uint256 formerBorrowBalance,
        uint256 formerCollateralBalance,
        uint256 repaid,
        uint256 seized
    ) internal returns (uint256 expectedSeized, uint256 expectedRepaid) {
        assertGt(repaid, 0);
        assertGt(seized, 0);

        uint256 currentBorrowBalance = morpho.borrowBalance(borrowedMarket.underlying, borrower);
        uint256 currentCollateralBalance = morpho.collateralBalance(collateralMarket.underlying, borrower);

        expectedRepaid = Math.min(formerBorrowBalance, toRepay);
        expectedSeized = (
            (expectedRepaid * borrowedMarket.price * 10 ** collateralMarket.decimals)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        ).percentMul(collateralMarket.liquidationBonus);
        if (expectedSeized > formerCollateralBalance) {
            expectedSeized = formerCollateralBalance;
            expectedRepaid = (
                (formerBorrowBalance * collateralMarket.price * 10 ** borrowedMarket.decimals)
                    / (borrowedMarket.price * 10 ** collateralMarket.decimals)
            ).percentDiv(collateralMarket.liquidationBonus);
        }

        assertEq(repaid, expectedRepaid, "repaid");
        assertEq(seized, expectedSeized, "seized");
        assertApproxEqAbs(currentBorrowBalance, formerBorrowBalance - expectedRepaid, 1, "borrow balance");
        assertEq(currentCollateralBalance, formerCollateralBalance - expectedSeized, "collateral balance");
    }

    function _assertEvents(
        address liquidator,
        address borrower,
        TestMarket storage collateralMarket,
        TestMarket storage borrowedMarket
    ) internal {
        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.Repaid(liquidator, borrower, borrowedMarket.underlying, 0, 0, 0);

        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.CollateralWithdrawn(address(0), borrower, liquidator, collateralMarket.underlying, 0, 0);

        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.Liquidated(address(user), borrower, borrowedMarket.underlying, 0, address(0), 0);
    }

    function _boundAmountWithPrice(uint256 amount, TestMarket memory market) internal view returns (uint256) {
        uint256 minAmount = MIN_PRICE_AMOUNT * (10 ** market.decimals) / market.price;
        return bound(amount, minAmount, MAX_AMOUNT);
    }

    function _overrideCollateral(
        TestMarket storage borrowedMarket,
        TestMarket storage collateralMarket,
        address borrower
    ) internal returns (uint256 borrowBalance, uint256 collateralBalance) {
        stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
            collateralMarket.underlying
        ).with_key(borrower).checked_write(morpho.scaledCollateralBalance(collateralMarket.underlying, borrower) / 2);
        borrowBalance = morpho.borrowBalance(borrowedMarket.underlying, borrower);
        collateralBalance = morpho.collateralBalance(collateralMarket.underlying, borrower);
    }
}
