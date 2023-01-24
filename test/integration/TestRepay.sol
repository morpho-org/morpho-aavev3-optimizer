// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRepay is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        return address(uint160(bound(uint256(uint160(onBehalf)), 1, type(uint160).max)));
    }

    function testShouldRepayPoolOnly(uint256 amount, address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableMarkets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = borrowableMarkets[marketIndex];

            uint256 borrowed = _boundBorrow(market, _boundSupply(market, amount)); // Don't go over the supply cap.

            uint256 promoted = borrowed.percentMul(50_00);
            promoter.approve(market.underlying, promoted);
            promoter.supply(market.underlying, promoted); // 50% peer-to-peer.
            amount = borrowed - promoted;

            _borrowNoCollateral(address(user1), market, borrowed, address(user1), address(user1), DEFAULT_MAX_LOOPS);

            uint256 balanceBefore = user1.balanceOf(market.underlying);
            uint256 morphoBalanceBefore = ERC20(market.debtToken).balanceOf(address(morpho));

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Repaid(address(user1), onBehalf, market.underlying, 0, 0, 0);

            uint256 repaid = user1.repay(market.underlying, amount, onBehalf);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pBorrow =
                morpho.scaledP2PBorrowBalance(market.underlying, onBehalf).rayMul(indexes.borrow.p2pIndex);
            uint256 poolBorrow =
                morpho.scaledPoolBorrowBalance(market.underlying, onBehalf).rayMul(indexes.borrow.poolIndex);

            assertGe(poolBorrow, 0, "poolBorrow == 0");
            assertLe(poolBorrow, borrowed - repaid, "poolBorrow > borrowed - repaid");
            assertLe(repaid, amount, "repaid > amount");
            assertApproxEqAbs(repaid, amount, 1, "repaid != amount");
            assertLe(p2pBorrow, promoted, "p2pBorrow > promoted");
            assertApproxEqAbs(p2pBorrow, promoted, 2, "p2pBorrow != promoted");

            assertApproxEqAbs(
                balanceBefore - user1.balanceOf(market.underlying), amount, 1, "balanceBefore - balanceAfter != amount"
            );
        }
    }

    function testShouldRevertRepayZero(address onBehalf) public {
        onBehalf = _boundOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.repay(markets[marketIndex].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertRepayOnBehalfZero(uint256 amount) public {
        amount = _boundAmount(amount);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.repay(markets[marketIndex].underlying, amount, address(0));
        }
    }

    function testShouldRevertRepayWhenMarketNotCreated(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.repay(sAvax, amount, onBehalf);
    }

    function testShouldRevertRepayWhenRepayPaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsRepayPaused(market.underlying, true);

            vm.expectRevert(Errors.RepayIsPaused.selector);
            user1.repay(market.underlying, amount, onBehalf);
        }
    }
}
