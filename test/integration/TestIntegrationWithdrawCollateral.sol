// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdrawCollateral is IntegrationTest {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    struct WithdrawCollateralTest {
        uint256 supplied;
        uint256 withdrawn;
        uint256 balanceBefore;
        uint256 morphoSupplyBefore;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function testShouldWithdrawAllCollateral(uint256 amount, address onBehalf, address receiver) public {
        WithdrawCollateralTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            test.supplied = _boundSupply(market, amount);
            amount = bound(amount, test.supplied + 1, type(uint256).max);

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, test.supplied);
            user.supplyCollateral(market.underlying, test.supplied, onBehalf);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.CollateralWithdrawn(address(user), onBehalf, receiver, market.underlying, test.supplied, 0);

            test.withdrawn = user.withdrawCollateral(market.underlying, amount, onBehalf, receiver);

            test.morphoMarket = morpho.market(market.underlying);
            test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
            test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
            test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);

            // Assert balances on Morpho.
            assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
            assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
            assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
            assertApproxLeAbs(test.withdrawn, test.supplied, 2, "withdrawn != supplied");

            // Assert Morpho getters.
            assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "supply != 0");
            assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");

            // Assert Morpho's position on pool.
            assertApproxEqAbs(
                market.supplyOf(address(morpho)), test.morphoSupplyBefore, 1, "morphoSupply != morphoSupplyBefore"
            );
            assertEq(market.variableBorrowOf(address(morpho)), 0, "morphoVariableBorrow != 0");
            assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

            // Assert receiver's underlying balance.
            assertApproxLeAbs(
                ERC20(market.underlying).balanceOf(receiver),
                test.balanceBefore + test.withdrawn,
                2,
                "balanceAfter != expectedBalance"
            );

            _assertMarketAccountingZero(test.morphoMarket);
        }
    }

    function testShouldNotWithdrawCollateralWhenLowHealthFactor(
        uint256 collateral,
        uint256 borrowed,
        uint256 withdrawn,
        address onBehalf,
        address receiver
    ) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                collateral = _boundCollateral(collateralMarket, collateral, borrowedMarket).percentAdd(1);
                uint256 borrowable = borrowedMarket.borrowable(collateralMarket, collateral).percentSub(4);
                borrowed = bound(
                    borrowed,
                    borrowedMarket.minAmount / 2,
                    Math.min(borrowable, Math.min(borrowedMarket.liquidity(), borrowedMarket.borrowGap()))
                );
                withdrawn = bound(
                    withdrawn,
                    collateral.zeroFloorSub(collateralMarket.minCollateral(borrowedMarket, borrowed)),
                    type(uint256).max
                );

                user.approve(collateralMarket.underlying, collateral);
                user.supplyCollateral(collateralMarket.underlying, collateral, onBehalf);

                user.borrow(borrowedMarket.underlying, borrowed, onBehalf, receiver);

                vm.expectRevert(Errors.UnauthorizedWithdraw.selector);
                user.withdrawCollateral(collateralMarket.underlying, withdrawn, onBehalf, receiver);
            }
        }
    }

    function testShouldNotWithdrawWhenNoCollateral(uint256 amount, address onBehalf, address receiver) public {
        WithdrawCollateralTest memory test;

        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectRevert(Errors.AmountIsZero.selector);
            user.withdrawCollateral(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldUpdateIndexesAfterWithdrawCollateral(uint256 blocks, uint256 amount, address onBehalf) public {
        blocks = _boundBlocks(blocks);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            user.approve(market.underlying, amount);
            user.supplyCollateral(market.underlying, amount, onBehalf);

            _forward(blocks);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            user.withdrawCollateral(market.underlying, amount, onBehalf);

            _assertMarketUpdatedIndexes(morpho.market(market.underlying), futureIndexes);
        }
    }

    function testShouldRevertWithdrawCollateralZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.withdrawCollateral(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertWithdrawCollateralOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.withdrawCollateral(testMarkets[underlyings[marketIndex]].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertWithdrawCollateralToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.withdrawCollateral(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertWithdrawCollateralWhenMarketNotCreated(
        address underlying,
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        _assumeNotUnderlying(underlying);

        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.withdrawCollateral(underlying, amount, onBehalf, receiver);
    }

    function testShouldRevertWithdrawCollateralWhenWithdrawCollateralPaused(
        uint256 amount,
        address onBehalf,
        address receiver
    ) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawCollateralIsPaused.selector);
            user.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertWithdrawCollateralWhenNotManaging(uint256 amount, address onBehalf, address receiver)
        public
    {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user.withdrawCollateral(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf);
        }
    }

    function testShouldWithdrawCollateralWhenEverythingElsePaused(uint256 amount, address onBehalf, address receiver)
        public
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            user.approve(market.underlying, amount);
            user.supplyCollateral(market.underlying, amount, onBehalf);

            morpho.setIsPausedForAllMarkets(true);
            morpho.setIsWithdrawCollateralPaused(market.underlying, false);

            user.withdrawCollateral(market.underlying, amount, onBehalf);
        }
    }
}
