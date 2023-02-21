// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationLiquidate is IntegrationTest {
    using WadRayMath for uint256;
    using stdStorage for StdStorage;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    uint256 internal constant MIN_AMOUNT = 10_000_000;

    struct LiquidateTest {
        uint256 supplied;
        uint256 borrowed;
        uint256 repaid;
        uint256 seized;
    }

    function testShouldNotLiquidateHealthyUser(address borrower, uint256 amount, uint256 toRepay) public {
        borrower = _boundAddressNotZero(borrower);

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
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

    function testShouldNotSeizeCollateralOfUserNotOnCollateralMarket(
        address borrower,
        uint256 amount,
        uint256 toRepay,
        uint256 indexShift
    ) public {
        borrower = _boundAddressNotZero(borrower);
        indexShift = bound(indexShift, 1, collateralUnderlyings.length - 1);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                assertGt(test.supplied, 0);
                assertGt(test.borrowed, 0);

                (uint256 borrowBalance,) = _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                address collateralUnderlying =
                    collateralUnderlyings[(collateralIndex + indexShift) % collateralUnderlyings.length];

                (test.repaid, test.seized) =
                    user.liquidate(borrowedMarket.underlying, collateralUnderlying, borrower, toRepay);

                assertEq(test.seized, 0, "seized");

                _assertLiquidation(
                    borrowedMarket,
                    testMarkets[collateralUnderlying],
                    borrower,
                    toRepay,
                    borrowBalance,
                    0,
                    test.repaid,
                    test.seized
                );
            }
        }
    }

    function testShouldNotLiquidateUserNotInBorrowMarket(
        address borrower,
        uint256 amount,
        uint256 toRepay,
        uint256 indexShift
    ) public {
        borrower = _boundAddressNotZero(borrower);
        indexShift = bound(indexShift, 1, borrowableUnderlyings.length - 1);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                assertGt(test.supplied, 0);
                assertGt(test.borrowed, 0);

                _overrideCollateral(borrowedMarket, collateralMarket, borrower);

                toRepay = bound(toRepay, Math.min(MIN_AMOUNT, test.borrowed), test.borrowed);

                user.approve(borrowedMarket.underlying, toRepay);

                address borrowedUnderlying =
                    borrowableUnderlyings[(borrowedIndex + indexShift) % borrowableUnderlyings.length];

                (test.repaid, test.seized) =
                    user.liquidate(borrowedUnderlying, collateralMarket.underlying, borrower, toRepay);

                assertEq(test.repaid, 0);
                assertEq(test.seized, 0);
            }
        }
    }

    function testLiquidateUnhealthyUser(address borrower, uint256 amount, uint256 promoted, uint256 toRepay) public {
        borrower = _boundAddressNotZero(borrower);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
                (test.supplied, test.borrowed) = _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                _promoteBorrow(promoter1, borrowedMarket, bound(promoted, 0, test.borrowed));

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
        borrower = _boundAddressNotZero(borrower);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
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
        borrower = _boundAddressNotZero(borrower);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
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
        borrower = _boundAddressNotZero(borrower);

        LiquidateTest memory test;

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
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
        borrower = _boundAddressNotZero(borrower);

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                amount = _boundBorrow(borrowedMarket, amount);
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
        borrower = _boundAddressNotZero(borrower);
        _assumeNotUnderlying(underlying);

        for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
            _revert();

            TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

            vm.expectRevert(); // Indexes calculation revert because indexes are updated before the market created check.
            user.liquidate(borrowedMarket.underlying, underlying, borrower, amount);
        }
    }

    function testShouldRevertWhenBorrowMarketNotCreated(address underlying, address borrower, uint256 amount) public {
        borrower = _boundAddressNotZero(borrower);
        _assumeNotUnderlying(underlying);

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            _revert();

            TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];

            vm.expectRevert(); // Indexes calculation revert because indexes are updated before the market created check.
            user.liquidate(underlying, collateralMarket.underlying, borrower, amount);
        }
    }

    function testShouldRevertWhenLiquidateCollateralIsPaused(address borrower, uint256 amount) public {
        borrower = _boundAddressNotZero(borrower);

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
        borrower = _boundAddressNotZero(borrower);

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
        // For now skip oracle sentinel check.
        uint256 closeFactor = Constants.MAX_CLOSE_FACTOR;

        expectedRepaid = Math.min(formerBorrowBalance.percentMul(closeFactor), toRepay);
        expectedSeized = (
            (expectedRepaid * borrowedMarket.price * 10 ** collateralMarket.decimals)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        ).percentMul(collateralMarket.liquidationBonus);
        if (expectedSeized > formerCollateralBalance) {
            expectedSeized = formerCollateralBalance;
            expectedRepaid = (
                (formerCollateralBalance * collateralMarket.price * 10 ** borrowedMarket.decimals)
                    / (borrowedMarket.price * 10 ** collateralMarket.decimals)
            ).percentDiv(collateralMarket.liquidationBonus);
        }

        assertEq(repaid, expectedRepaid, "repaid");
        assertEq(seized, expectedSeized, "seized");
        assertApproxEqAbs(
            morpho.borrowBalance(borrowedMarket.underlying, borrower),
            formerBorrowBalance - expectedRepaid,
            1,
            "borrow balance"
        );
        assertEq(
            morpho.collateralBalance(collateralMarket.underlying, borrower),
            formerCollateralBalance - expectedSeized,
            "collateral balance"
        );
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

    function _overrideCollateral(
        TestMarket storage borrowedMarket,
        TestMarket storage collateralMarket,
        address borrower
    ) internal returns (uint256 borrowBalance, uint256 collateralBalance) {
        stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
            collateralMarket.underlying
        ).with_key(borrower).checked_write(
            morpho.scaledCollateralBalance(collateralMarket.underlying, borrower).percentSub(
                collateralMarket.ltv.percentDiv(collateralMarket.lt)
            )
        );

        borrowBalance = morpho.borrowBalance(borrowedMarket.underlying, borrower);
        collateralBalance = morpho.collateralBalance(collateralMarket.underlying, borrower);
    }
}
