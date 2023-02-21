// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";
import "src/interfaces/IMorphoExtended.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";

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

                amount = _boundCollateral(collateralMarket, amount, borrowedMarket);

                _borrowWithCollateral(
                    borrower, collateralMarket, borrowedMarket, amount, borrower, borrower, DEFAULT_MAX_ITERATIONS
                );

                Types.LiquidityData memory data = morpho.liquidityData(borrower);
                (uint256 totalCollateralBase, uint256 totalDebtBase,,,, uint256 healthFactor) =
                    pool.getUserAccountData(address(morpho));

                // Sanity checks: no peer-to-peer.
                assertEq(morpho.market(borrowedMarket.underlying).deltas.supply.scaledP2PTotal, 0);
                assertEq(morpho.market(borrowedMarket.underlying).deltas.borrow.scaledP2PTotal, 0);
                assertEq(morpho.market(collateralMarket.underlying).deltas.supply.scaledP2PTotal, 0);
                assertEq(morpho.market(collateralMarket.underlying).deltas.borrow.scaledP2PTotal, 0);

                assertApproxEqAbs(data.debt, totalDebtBase, 1, "debt");
                assertApproxEqAbs(data.collateral, totalCollateralBase, 1, "collateral");
                assertApproxLeAbs(data.maxDebt.wadDiv(data.debt), healthFactor, 1e5, "health factor incorrect");
            }
        }
    }

    function testLiquidityDataMultiple() public {
        IMorphoExtended morphoExtended = IMorphoExtended(address(morpho));
        uint256 amount = 10e10;

        Types.LiquidityVars memory vars;
        // emode category is 0 here
        vars.oracle = IAaveOracle(IPoolAddressesProvider(morpho.ADDRESSES_PROVIDER()).getPriceOracle());
        vars.user = address(user);

        uint256 avgLT;
        uint256 collateral;
        uint256 debt;

        uint256 wbtcCollateral = _boundSupply(testMarkets[wbtc], amount);
        user.approve(wbtc, wbtcCollateral);
        user.supplyCollateral(wbtc, wbtcCollateral);
        (uint256 collateralWbtc,,) = morphoExtended._collateralData(wbtc, vars);
        (,, uint256 ltWbtc,) = morphoExtended._assetLiquidityData(wbtc, vars);
        collateral += collateralWbtc;
        avgLT += collateralWbtc * ltWbtc;

        uint256 wethCollateral = _boundSupply(testMarkets[weth], amount);
        user.approve(weth, wethCollateral);
        user.supplyCollateral(weth, wethCollateral);
        (uint256 collateralWeth,, uint256 maxDebtWeth) = morphoExtended._collateralData(weth, vars);
        (,, uint256 ltWeth,) = morphoExtended._assetLiquidityData(weth, vars);
        collateral += collateralWeth;
        avgLT += collateralWeth * ltWeth;

        TestMarket storage borrowedMarket;
        borrowedMarket = testMarkets[usdc];
        uint256 borrowable = borrowedMarket.borrowable(testMarkets[wbtc], wbtcCollateral);
        borrowable = bound(
            borrowable,
            borrowedMarket.minAmount / 2,
            Math.min(borrowable, Math.min(borrowedMarket.liquidity(), borrowedMarket.borrowGap()))
        );
        user.borrow(usdc, borrowable);
        debt = morphoExtended._debt(usdc, vars);

        avgLT = avgLT / collateral;
        uint256 simulatedAaveHF = collateral.percentMul(avgLT).wadDiv(debt);

        Types.LiquidityData memory data = morpho.liquidityData(address(user));
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,, uint256 healthFactor) =
            pool.getUserAccountData(address(morpho));

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

        // assertApproxEqAbs(data.debt, totalDebtBase, 1e3, "debt");
        // assertApproxEqAbs(data.debt, totalDebtBase, 10e2, "debt");
        // assertApproxEqAbs(data.collateral, totalCollateralBase, 10e2, "collateral");
        // assertApproxLeAbs(data.maxDebt.wadDiv(data.debt), healthFactor, 1e5, "health factor incorrect");
        assertApproxLeAbs(simulatedAaveHF, healthFactor, 1e5, "health factor incorrect");
    }
}
