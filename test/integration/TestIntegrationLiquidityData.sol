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

                assertApproxEqAbs(data.debt, totalDebtBase, 1, "debt");
                assertApproxLeAbs(data.maxDebt.wadDiv(data.debt), healthFactor, 1e5, "health factor uncorrect");
            }
        }
    }
}
