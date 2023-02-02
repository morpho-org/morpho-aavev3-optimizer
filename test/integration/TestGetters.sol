// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationGetters is IntegrationTest {
    using WadRayMath for uint256;

    function testUpdatedPoolIndexes(uint256 blocks) public {
        blocks = _boundBlocks(blocks);

        _forward(blocks);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];
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

    // function testSupplyBalanceInterests(uint256 blocks) public {
    //     blocks = _boundBlocks(blocks);

    //     for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
    //         _revert();

    //         TestMarket storage market = testMarkets[underlyings[marketIndex]];

    //         (, amount) = _borrowUpTo(market, market, amount, 100_00);
    //         amount /= 2; // 50% peer-to-peer.

    //         user.approve(market.underlying, amount);
    //         user.supply(market.underlying, amount, onBehalf);

    //         _forward(blocks);

    //         Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);

    //         assertEq(
    //             morpho.supplyBalance(market.underlying, onBehalf),
    //             pool.getReserveNormalizedIncome(market.underlying),
    //             "poolSupplyIndex != truePoolSupplyIndex"
    //         );

    //         assertEq(
    //             indexes.borrow.poolIndex,
    //             pool.getReserveNormalizedVariableDebt(market.underlying),
    //             "poolBorrowIndex != truePoolBorrowIndex"
    //         );
    //     }
    // }
}
