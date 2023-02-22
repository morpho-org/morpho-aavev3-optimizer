// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationGetters is IntegrationTest {
    using WadRayMath for uint256;

    function testUpdatedPoolIndexes(uint256 blocks, uint256 supplied, uint256 borrowed) public {
        blocks = _boundBlocks(blocks);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            supplied = _boundSupply(market, supplied);
            borrowed = _boundBorrow(market, borrowed);

            user.approve(market.underlying, supplied);
            user.supply(market.underlying, supplied);
            if (market.isBorrowable) {
                _borrowWithoutCollateral(
                    address(user), market, supplied, address(user), address(user), DEFAULT_MAX_ITERATIONS
                );
            }

            _forward(blocks);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);

            assertEq(
                indexes.supply.poolIndex,
                pool.getReserveNormalizedIncome(market.underlying),
                "poolSupplyIndex != truePoolSupplyIndex"
            );

            assertEq(
                indexes.borrow.poolIndex,
                pool.getReserveNormalizedVariableDebt(market.underlying),
                "poolBorrowIndex != truePoolBorrowIndex"
            );
        }
    }

    function testBalanceInterests(uint256 blocks, uint256 supplied, uint256 borrowed) public {
        blocks = _boundBlocks(blocks);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            supplied = _boundSupply(market, supplied);
            borrowed = _boundBorrow(market, borrowed);

            user.approve(market.underlying, supplied);
            user.supply(market.underlying, supplied);
            if (market.isBorrowable) {
                _borrowWithoutCollateral(
                    address(user), market, supplied, address(user), address(user), DEFAULT_MAX_ITERATIONS
                );
            }

            uint256 supplyBalanceBefore = morpho.supplyBalance(market.underlying, address(user));
            uint256 borrowBalanceBefore = morpho.borrowBalance(market.underlying, address(user));

            DataTypes.ReserveData memory reserve = pool.getReserveData(market.underlying);

            _forward(blocks);

            assertEq(
                morpho.supplyBalance(market.underlying, address(user)),
                supplyBalanceBefore + reserve.currentLiquidityRate * blocks * BLOCK_TIME,
                "supplyBalanceAfter <= supplyBalanceBefore + interestsAccrued"
            );

            if (market.isBorrowable) {
                assertEq(
                    morpho.borrowBalance(market.underlying, address(user)),
                    borrowBalanceBefore + reserve.currentVariableBorrowRate * blocks * BLOCK_TIME,
                    "borrowBalanceAfter <= borrowBalanceBefore + interestsAccrued"
                );
            } else {
                assertEq(morpho.borrowBalance(market.underlying, address(user)), 0, "borrowBalanceAfter != 0");
            }
        }
    }
}