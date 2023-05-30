// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../helpers/ProductionTest.sol";

contract TestProdLifecycle is ProductionTest {
    using WadRayMath for uint256;

    function _beforeSupplyCollateral(MarketSideTest memory collateral) internal virtual {}

    function _beforeSupply(MarketSideTest memory supply) internal virtual {}

    function _beforeBorrow(MarketSideTest memory borrow) internal virtual {}

    struct MorphoPosition {
        uint256 scaledP2P;
        uint256 scaledPool;
        //
        uint256 p2p;
        uint256 pool;
        uint256 total;
    }

    struct MarketSideTest {
        Types.Indexes256 indexes;
        uint256 amount;
        //
        uint256 morphoPoolSupplyBefore;
        uint256 morphoPoolBorrowBefore;
        uint256 morphoUnderlyingBalanceBefore;
        //
        MorphoPosition position;
    }

    function _initMarketSideTest(TestMarket storage market, uint256 amount)
        internal
        view
        virtual
        returns (MarketSideTest memory test)
    {
        test.morphoPoolSupplyBefore = ERC20(market.aToken).balanceOf(address(morpho));
        test.morphoPoolBorrowBefore = ERC20(market.variableDebtToken).balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = ERC20(market.underlying).balanceOf(address(morpho));

        test.amount = amount;
    }

    function _updateSupplyTest(address underlying, MarketSideTest memory test) internal view {
        test.indexes = morpho.updatedIndexes(underlying);

        test.position.p2p = test.position.scaledP2P.rayMul(test.indexes.supply.p2pIndex);
        test.position.pool = test.position.scaledPool.rayMul(test.indexes.supply.poolIndex);
        test.position.total = test.position.p2p + test.position.pool;
    }

    function _updateBorrowTest(address underlying, MarketSideTest memory test) internal view {
        test.indexes = morpho.updatedIndexes(underlying);

        test.position.p2p = test.position.scaledP2P.rayMul(test.indexes.borrow.p2pIndex);
        test.position.pool = test.position.scaledPool.rayMul(test.indexes.borrow.poolIndex);
        test.position.total = test.position.p2p + test.position.pool;
    }

    function _updateCollateralTest(address underlying, MarketSideTest memory test) internal view {
        test.indexes = morpho.updatedIndexes(underlying);

        test.position.pool = test.position.scaledPool.rayMul(test.indexes.supply.poolIndex);
        test.position.total = test.position.pool;
    }

    function _supplyCollateral(TestMarket storage market, uint256 amount)
        internal
        virtual
        returns (MarketSideTest memory collateral)
    {
        collateral = _initMarketSideTest(market, amount);

        _beforeSupplyCollateral(collateral);

        user.approve(market.underlying, collateral.amount);
        user.supplyCollateral(market.underlying, collateral.amount, address(user));

        collateral.position.scaledPool = morpho.scaledCollateralBalance(market.underlying, address(user));

        _updateCollateralTest(market.underlying, collateral);
    }

    function _testSupplyCollateral(
        TestMarket storage testMarket,
        Types.Market memory market,
        MarketSideTest memory collateral
    ) internal virtual {
        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(user)),
            0,
            string.concat(testMarket.symbol, " balance after collateral supply")
        );
        assertApproxEqAbs(
            collateral.position.total, collateral.amount, 1, string.concat(testMarket.symbol, " total collateral")
        );

        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(morpho)),
            collateral.morphoUnderlyingBalanceBefore,
            string.concat(testMarket.symbol, " morpho balance")
        );
        assertApproxEqAbs(
            ERC20(testMarket.aToken).balanceOf(address(morpho)),
            collateral.morphoPoolSupplyBefore + collateral.position.pool,
            10,
            string.concat(testMarket.symbol, " morpho pool supply")
        );
        assertApproxEqAbs(
            ERC20(testMarket.variableDebtToken).balanceOf(address(morpho)) + collateral.position.p2p,
            collateral.morphoPoolBorrowBefore,
            10,
            string.concat(testMarket.symbol, " morpho pool borrow")
        );

        _forward(100_000);

        _updateCollateralTest(market.underlying, collateral);
    }

    function _supply(TestMarket storage market, uint256 amount)
        internal
        virtual
        returns (MarketSideTest memory supply)
    {
        supply = _initMarketSideTest(market, amount);

        _beforeSupply(supply);

        user.approve(market.underlying, supply.amount);
        user.supply(market.underlying, supply.amount, address(user));

        supply.position.scaledP2P = morpho.scaledP2PSupplyBalance(market.underlying, address(user));
        supply.position.scaledPool = morpho.scaledPoolSupplyBalance(market.underlying, address(user));

        _updateSupplyTest(market.underlying, supply);
    }

    function _testSupply(TestMarket storage testMarket, Types.Market memory market, MarketSideTest memory supply)
        internal
        virtual
    {
        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(user)),
            0,
            string.concat(testMarket.symbol, " balance after supply")
        );
        assertApproxEqAbs(supply.position.total, supply.amount, 1, string.concat(testMarket.symbol, " total supply"));

        if (market.pauseStatuses.isP2PDisabled) {
            assertEq(supply.position.scaledP2P, 0, string.concat(testMarket.symbol, " borrow delta matched"));
        } else {
            uint256 underlyingBorrowDelta = market.deltas.borrow.scaledDelta.rayMul(supply.indexes.borrow.poolIndex);
            if (underlyingBorrowDelta <= supply.amount) {
                assertGe(
                    supply.position.p2p,
                    underlyingBorrowDelta,
                    string.concat(testMarket.symbol, " borrow delta minimum match")
                );
            } else {
                assertApproxEqAbs(
                    supply.position.p2p, supply.amount, 1, string.concat(testMarket.symbol, " borrow delta full match")
                );
            }
        }

        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(morpho)),
            supply.morphoUnderlyingBalanceBefore,
            string.concat(testMarket.symbol, " morpho balance")
        );
        assertApproxEqAbs(
            ERC20(testMarket.aToken).balanceOf(address(morpho)),
            supply.morphoPoolSupplyBefore + supply.position.pool,
            10,
            string.concat(testMarket.symbol, " morpho pool supply")
        );
        assertApproxEqAbs(
            ERC20(testMarket.variableDebtToken).balanceOf(address(morpho)) + supply.position.p2p,
            supply.morphoPoolBorrowBefore,
            10,
            string.concat(testMarket.symbol, " morpho pool borrow")
        );

        _forward(100_000);

        _updateSupplyTest(market.underlying, supply);
    }

    function _borrow(TestMarket storage market, uint256 amount)
        internal
        virtual
        returns (MarketSideTest memory borrow)
    {
        borrow = _initMarketSideTest(market, amount);

        _beforeBorrow(borrow);

        user.borrow(market.aToken, borrow.amount);

        borrow.position.scaledP2P = morpho.scaledP2PBorrowBalance(market.underlying, address(user));
        borrow.position.scaledPool = morpho.scaledPoolBorrowBalance(market.underlying, address(user));

        _updateBorrowTest(market.underlying, borrow);
    }

    function _testBorrow(TestMarket storage testMarket, Types.Market memory market, MarketSideTest memory borrow)
        internal
        virtual
    {
        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(user)),
            borrow.amount,
            string.concat(testMarket.symbol, " balance after borrow")
        );
        assertApproxEqAbs(borrow.position.total, borrow.amount, 1, string.concat(testMarket.symbol, " total borrow"));
        if (market.pauseStatuses.isP2PDisabled) {
            assertEq(borrow.position.scaledP2P, 0, string.concat(testMarket.symbol, " supply delta matched"));
        } else {
            uint256 underlyingSupplyDelta = market.deltas.supply.scaledDelta.rayMul(borrow.indexes.supply.poolIndex);
            if (underlyingSupplyDelta <= borrow.amount) {
                assertGe(
                    borrow.position.p2p,
                    underlyingSupplyDelta,
                    string.concat(testMarket.symbol, " supply delta minimum match")
                );
            } else {
                assertApproxEqAbs(
                    borrow.position.p2p, borrow.amount, 1, string.concat(testMarket.symbol, " supply delta full match")
                );
            }
        }

        assertEq(
            ERC20(testMarket.underlying).balanceOf(address(morpho)),
            borrow.morphoUnderlyingBalanceBefore,
            string.concat(testMarket.symbol, " morpho borrowed balance")
        );
        assertApproxEqAbs(
            ERC20(testMarket.aToken).balanceOf(address(morpho)) + borrow.position.p2p,
            borrow.morphoPoolSupplyBefore,
            2,
            string.concat(testMarket.symbol, " morpho borrowed pool supply")
        );
        assertApproxEqAbs(
            ERC20(testMarket.variableDebtToken).balanceOf(address(morpho)),
            borrow.morphoPoolBorrowBefore + borrow.position.pool,
            1,
            string.concat(testMarket.symbol, " morpho borrowed pool borrow")
        );

        _forward(100_000);

        _updateBorrowTest(market.underlying, borrow);
    }

    function _repay(TestMarket storage market, MarketSideTest memory borrow) internal virtual {
        _updateBorrowTest(market.underlying, borrow);

        user.approve(market.underlying, borrow.position.total);
        user.repay(market.aToken, type(uint256).max, address(user));
    }

    function _testRepay(TestMarket storage market, MarketSideTest memory borrow) internal virtual {
        assertApproxEqAbs(
            ERC20(market.underlying).balanceOf(address(user)),
            0,
            10 ** (market.decimals / 2),
            string.concat(market.symbol, " borrow after repay")
        );

        _updateBorrowTest(market.underlying, borrow);

        assertEq(borrow.position.p2p, 0, string.concat(market.symbol, " p2p borrow after repay"));
        assertEq(borrow.position.pool, 0, string.concat(market.symbol, " pool borrow after repay"));
        assertEq(borrow.position.total, 0, string.concat(market.symbol, " total borrow after repay"));
    }

    function _withdraw(TestMarket storage market, MarketSideTest memory supply) internal virtual {
        _updateSupplyTest(market.underlying, supply);

        user.withdraw(market.underlying, type(uint256).max);
    }

    function _testWithdraw(TestMarket storage market, MarketSideTest memory supply) internal virtual {
        assertApproxEqAbs(
            ERC20(market.underlying).balanceOf(address(user)),
            supply.position.total,
            10 ** (market.decimals / 2),
            string.concat(market.symbol, " supply after withdraw")
        );

        _updateSupplyTest(market.underlying, supply);

        assertEq(supply.position.p2p, 0, string.concat(market.symbol, " p2p supply after withdraw"));
        assertEq(supply.position.pool, 0, string.concat(market.symbol, " pool supply after withdraw"));
        assertEq(supply.position.total, 0, string.concat(market.symbol, " total supply after withdraw"));
    }

    function _withdrawCollateral(TestMarket storage market, MarketSideTest memory collateral) internal virtual {
        _updateSupplyTest(market.underlying, collateral);

        user.withdraw(market.underlying, type(uint256).max);
    }

    function _testWithdrawCollateral(TestMarket storage market, MarketSideTest memory collateral) internal virtual {
        assertApproxEqAbs(
            ERC20(market.underlying).balanceOf(address(user)),
            collateral.position.total,
            10 ** (market.decimals / 2),
            string.concat(market.symbol, " collateral after withdraw")
        );

        _updateSupplyTest(market.underlying, collateral);

        assertEq(collateral.position.p2p, 0, string.concat(market.symbol, " p2p supply after withdraw"));
        assertEq(collateral.position.pool, 0, string.concat(market.symbol, " pool supply after withdraw"));
        assertEq(collateral.position.total, 0, string.concat(market.symbol, " total supply after withdraw"));
    }

    function testShouldSupplyCollateralSupplyBorrowWithdrawRepayWithdrawCollateralAllMarkets(uint96 amount) public {
        for (
            uint256 collateralMarketIndex; collateralMarketIndex < collateralUnderlyings.length; ++collateralMarketIndex
        ) {
            TestMarket storage collateralTestMarket = testMarkets[collateralUnderlyings[collateralMarketIndex]];
            Types.Market memory collateralMarket = morpho.market(collateralTestMarket.underlying);

            if (collateralMarket.pauseStatuses.isSupplyCollateralPaused) continue;

            for (uint256 supplyMarketIndex; supplyMarketIndex < allUnderlyings.length; ++supplyMarketIndex) {
                TestMarket storage supplyTestMarket = testMarkets[allUnderlyings[supplyMarketIndex]];
                Types.Market memory supplyMarket = morpho.market(supplyTestMarket.underlying);

                for (
                    uint256 borrowMarketIndex;
                    borrowMarketIndex < borrowableInEModeUnderlyings.length;
                    ++borrowMarketIndex
                ) {
                    _revert();

                    TestMarket storage borrowTestMarket = testMarkets[borrowableInEModeUnderlyings[borrowMarketIndex]];
                    Types.Market memory borrowMarket = morpho.market(borrowTestMarket.underlying);

                    uint256 borrowedPrice = oracle.getAssetPrice(borrowTestMarket.underlying);
                    uint256 borrowAmount = _boundBorrowAmount(borrowMarket, amount, borrowedPrice);
                    uint256 supplyAmount = _getMinimumCollateralAmount(
                        borrowAmount,
                        borrowedPrice,
                        borrowMarket.decimals,
                        oracle.getAssetPrice(supplyMarket.underlying),
                        supplyMarket.decimals,
                        supplyMarket.ltv
                    ).wadMul(1.001 ether);

                    MarketSideTest memory collateral = _supplyCollateral(supplyMarket, supplyAmount);
                    _testSupplyCollateral(collateralTestMarket, collateral);

                    MarketSideTest memory supply;
                    if (!supplyMarket.pauseStatuses.isSupplyPaused) {
                        supply = _supply(supplyMarket, supplyAmount);
                        _testSupply(supplyTestMarket, supply);
                    }

                    MarketSideTest memory borrow;
                    if (!borrowMarket.pauseStatuses.isBorrowPaused) {
                        borrow = _borrow(borrowMarket, borrowAmount);
                        _testBorrow(borrowTestMarket, borrow);
                    }

                    if (!supplyMarket.pauseStatuses.isSupplyPaused && !supplyMarket.pauseStatuses.isWithdrawPaused) {
                        _withdraw(supplyTestMarket, supply);
                        _testWithdraw(supplyTestMarket, supply);
                    }

                    if (!borrowMarket.pauseStatuses.isBorrowPaused && !borrowMarket.pauseStatuses.isRepayPaused) {
                        _repay(borrowTestMarket, borrow);
                        _testRepay(borrowTestMarket, borrow);
                    }

                    if (collateralMarket.pauseStatuses.isWithdrawCollateralPaused) continue;

                    _withdrawCollateral(collateralTestMarket, supply);
                    _testWithdrawCollateral(collateralTestMarket, supply);
                }
            }
        }
    }

    // function testShouldNotBorrowWithoutEnoughCollateral(uint96 amount) public {
    //     for (uint256 supplyMarketIndex; supplyMarketIndex < collateralMarkets.length; ++supplyMarketIndex) {
    //         TestMarket memory supplyMarket = collateralMarkets[supplyMarketIndex];

    //         if (supplyMarket.pauseStatuses.isSupplyPaused) continue;

    //         for (uint256 borrowMarketIndex; borrowMarketIndex < borrowableMarkets.length; ++borrowMarketIndex) {
    //             _revert();

    //             TestMarket memory borrowMarket = borrowableMarkets[borrowMarketIndex];

    //             if (borrowMarket.pauseStatuses.isBorrowPaused) continue;

    //             uint256 borrowedPrice = oracle.getAssetPrice(borrowMarket.underlying);
    //             uint256 borrowAmount = _boundBorrowAmount(borrowMarket, amount, borrowedPrice);
    //             uint256 supplyAmount = _getMinimumCollateralAmount(
    //                 borrowAmount,
    //                 borrowedPrice,
    //                 borrowMarket.decimals,
    //                 oracle.getAssetPrice(supplyMarket.underlying),
    //                 supplyMarket.decimals,
    //                 supplyMarket.ltv
    //             ).wadMul(0.95 ether);

    //             _supply(supplyMarket, supplyAmount);

    //             vm.expectRevert(Errors.UnauthorisedBorrow.selector);
    //             user.borrow(borrowMarket.poolToken, borrowAmount);
    //         }
    //     }
    // }

    function testShouldNotSupplyZeroAmount() public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.supply(allUnderlyings[i], 0, address(user));
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 amount) public {
        vm.assume(amount > 0);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.supply(allUnderlyings[i], amount, address(0));
        }
    }

    function testShouldNotBorrowZeroAmount() public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.borrow(allUnderlyings[i], 0);
        }
    }

    function testShouldNotRepayZeroAmount() public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.repay(allUnderlyings[i], 0, address(user));
        }
    }

    function testShouldNotWithdrawZeroAmount() public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.withdraw(allUnderlyings[i], 0);
        }
    }

    function testShouldNotSupplyWhenPaused(uint96 amount) public {
        vm.assume(amount > 0);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            TestMarket storage market = testMarkets[allUnderlyings[i]];
            if (!morpho.market(market.underlying).pauseStatuses.isSupplyPaused) continue;

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user.supply(market.underlying, amount);
        }
    }

    function testShouldNotBorrowWhenPaused(uint96 amount) public {
        vm.assume(amount > 0);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            TestMarket storage market = testMarkets[allUnderlyings[i]];
            if (!morpho.market(market.underlying).pauseStatuses.isBorrowPaused) continue;

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user.borrow(market.underlying, amount);
        }
    }

    function testShouldNotRepayWhenPaused(uint96 amount) public {
        vm.assume(amount > 0);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            TestMarket storage market = testMarkets[allUnderlyings[i]];
            if (!morpho.market(market.underlying).pauseStatuses.isRepayPaused) continue;

            vm.expectRevert(Errors.RepayIsPaused.selector);
            user.repay(market.underlying, type(uint256).max);
        }
    }

    function testShouldNotWithdrawWhenPaused(uint96 amount) public {
        vm.assume(amount > 0);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            TestMarket storage market = testMarkets[allUnderlyings[i]];
            if (!morpho.market(market.underlying).pauseStatuses.isWithdrawPaused) continue;

            vm.expectRevert(Errors.WithdrawIsPaused.selector);
            user.withdraw(market.underlying, type(uint256).max);
        }
    }
}
