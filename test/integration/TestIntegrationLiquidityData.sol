// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationLiquididityData is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    function testLiquidityDataSingle(address borrower, uint256 amount) public {
        vm.assume(borrower != address(0));

        for (uint256 collateralIndex; collateralIndex < collateralUnderlyings.length; ++collateralIndex) {
            for (uint256 borrowedIndex; borrowedIndex < borrowableUnderlyings.length; ++borrowedIndex) {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedIndex]];

                if (collateralMarket.underlying == borrowedMarket.underlying) continue;

                amount = _boundCollateral(collateralMarket, amount, borrowedMarket);

                _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                Types.LiquidityData memory data = morpho.liquidityData(borrower);
                (, uint256 totalDebtBase,,,, uint256 healthFactor) = pool.getUserAccountData(address(morpho));

                // Sanity checks: no peer-to-peer.
                assertEq(morpho.market(borrowedMarket.underlying).deltas.supply.scaledP2PTotal, 0);
                assertEq(morpho.market(borrowedMarket.underlying).deltas.borrow.scaledP2PTotal, 0);
                assertEq(morpho.market(collateralMarket.underlying).deltas.supply.scaledP2PTotal, 0);
                assertEq(morpho.market(collateralMarket.underlying).deltas.borrow.scaledP2PTotal, 0);

                assertApproxEqAbs(data.debt, totalDebtBase, 1, "debt");
                assertApproxLeAbs(data.maxDebt.wadDiv(data.debt), healthFactor, 1e5, "health factor incorrect");
            }
        }
    }

    function testLiquidityDataMultiple(uint256 amount) public {
        TestMarket storage borrowedMarket;

        uint256 wbtcCollateral = _boundSupply(testMarkets[wbtc], amount);
        user.approve(wbtc, wbtcCollateral);
        user.supplyCollateral(wbtc, wbtcCollateral);

        uint256 wethCollateral = _boundSupply(testMarkets[weth], amount);
        user.approve(weth, wethCollateral);
        user.supplyCollateral(weth, wethCollateral);

        uint256 daiCollateral = _boundSupply(testMarkets[dai], amount);
        user.approve(dai, daiCollateral);
        user.supplyCollateral(dai, daiCollateral);

        borrowedMarket = testMarkets[usdc];
        uint256 borrowable = borrowedMarket.borrowable(testMarkets[wbtc], wbtcCollateral);
        borrowable = bound(
            borrowable,
            borrowedMarket.minAmount / 2,
            Math.min(borrowable, Math.min(borrowedMarket.liquidity(), borrowedMarket.borrowGap()))
        );
        user.borrow(usdc, borrowable);

        borrowedMarket = testMarkets[link];
        borrowable = borrowedMarket.borrowable(testMarkets[dai], daiCollateral);
        borrowable = bound(
            borrowable,
            borrowedMarket.minAmount / 2,
            Math.min(borrowable, Math.min(borrowedMarket.liquidity(), borrowedMarket.borrowGap()))
        );
        user.borrow(link, borrowable);

        Types.LiquidityData memory data = morpho.liquidityData(address(user));
        (, uint256 totalDebtBase,,,, uint256 healthFactor) = pool.getUserAccountData(address(morpho));

        // Sanity checks: no peer-to-peer.
        assertEq(morpho.market(wbtc).deltas.supply.scaledP2PTotal, 0);
        assertEq(morpho.market(wbtc).deltas.borrow.scaledP2PTotal, 0);
        assertEq(morpho.market(weth).deltas.supply.scaledP2PTotal, 0);
        assertEq(morpho.market(weth).deltas.borrow.scaledP2PTotal, 0);
        assertEq(morpho.market(dai).deltas.supply.scaledP2PTotal, 0);
        assertEq(morpho.market(dai).deltas.borrow.scaledP2PTotal, 0);
        assertEq(morpho.market(usdc).deltas.supply.scaledP2PTotal, 0);
        assertEq(morpho.market(usdc).deltas.borrow.scaledP2PTotal, 0);
        assertEq(morpho.market(link).deltas.supply.scaledP2PTotal, 0);
        assertEq(morpho.market(link).deltas.borrow.scaledP2PTotal, 0);

        assertApproxEqAbs(data.debt, totalDebtBase, 1e3, "debt");
        assertApproxLeAbs(data.maxDebt.wadDiv(data.debt), healthFactor, 1e5, "health factor incorrect");
    }
}
