// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationIndexes is IntegrationTest {
    using WadRayMath for uint256;

    function testUpdatedPoolIndexes(uint256 blocks) public {
        blocks = bound(blocks, 1, type(uint32).max);

        _forward(blocks);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];
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
}
