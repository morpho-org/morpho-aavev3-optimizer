// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestWithdraw is IntegrationTest {
    using WadRayMath for uint256;

    function testShouldWithdrawPoolOnly(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            uint256 supplied = _borrow50Pct(market, amount);

            user1.approve(market.underlying, supplied);
            user1.supply(market.underlying, supplied); // >= 50% pool.

            amount = supplied / 2;
            uint256 withdrawn = user1.withdraw(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);
            uint256 p2pSupply =
                morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex);
            uint256 poolSupply =
                morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex);
            uint256 totalSupply = poolSupply + p2pSupply;

            assertGe(poolSupply, 0, "poolSupply == 0");
            assertLe(poolSupply, amount, "poolSupply > amount");
            assertEq(withdrawn, amount, "withdrawn != amount");
            assertLe(p2pSupply, amount, "p2pSupply > amount");
            assertApproxEqAbs(totalSupply, amount, 2, "supply != amount");
        }
    }

    function testShouldWithdrawAll(uint256 amount, uint256 input) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            amount = _borrow50Pct(market, amount);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount); // >= 50% pool.

            input = bound(input, amount + 1, type(uint256).max);

            uint256 withdrawn = user1.withdraw(market.underlying, input);

            uint256 p2pSupply = morpho.scaledP2PSupplyBalance(market.underlying, address(user1));
            uint256 poolSupply = morpho.scaledPoolSupplyBalance(market.underlying, address(user1));

            assertEq(p2pSupply, 0, "p2pSupply != 0");
            assertEq(poolSupply, 0, "poolSupply != 0");
            assertLe(withdrawn, amount, "withdrawn > amount");
            assertApproxEqAbs(withdrawn, amount, 2, "withdrawn != amount");
        }
    }

    function testShouldRevertWithdrawZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertWithdrawOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertWithdrawToZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.withdraw(markets[marketIndex].underlying, 100, address(user1), address(0));
        }
    }

    function testShouldRevertWithdrawWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.withdraw(sAvax, 100);
    }

    function testShouldRevertWithdrawWhenWithdrawPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsWithdrawPaused(market.underlying, true);

            vm.expectRevert(Errors.WithdrawIsPaused.selector);
            user1.withdraw(market.underlying, 100);
        }
    }

    function testShouldRevertWithdrawWhenNotManaging(address managed) public {
        vm.assume(managed != address(0) && managed != address(user1));

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user1.withdraw(markets[marketIndex].underlying, 100, managed);
        }
    }

    function testShouldWithdrawWhenWithdrawCollateralPaused() public {
        uint256 amount = 100;

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount);

            morpho.setIsWithdrawCollateralPaused(market.underlying, true);

            user1.withdraw(market.underlying, amount);
        }
    }
}
