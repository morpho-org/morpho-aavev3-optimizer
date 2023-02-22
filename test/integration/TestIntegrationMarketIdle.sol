// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MarketLib} from "src/libraries/MarketLib.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMarketIdle is IntegrationTest {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using MarketLib for Types.Market;
    using Math for uint256;
    using TestMarketLib for TestMarket;

    Types.Market internal market;

    function testIncreaseIdleWhenNoSupplyCap(Types.Market memory _market, uint256 amount) public {
        TestMarket storage testMarket = testMarkets[dai];

        market = _market;

        _setSupplyCap(testMarket, 0);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);
        assertEq(suppliable, amount, "suppliable");
        assertEq(idleSupplyIncrease, 0, "idleSupplyIncrease");
    }

    function testIncreaseIdleWhenSupplyGapIsLarger(Types.Market memory _market, uint256 amount, uint256 supplyGap)
        public
    {
        TestMarket storage testMarket = testMarkets[dai];
        supplyGap = _setSupplyGap(testMarket, bound(supplyGap, (10 ** testMarket.decimals), testMarket.maxAmount));

        _market.aToken = testMarket.aToken;
        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);

        market = _market;

        amount = bound(amount, testMarket.minAmount, supplyGap);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);

        assertEq(suppliable, amount, "suppliable");
        assertEq(idleSupplyIncrease, 0, "idleSupplyIncrease");
        assertEq(market.idleSupply, _market.idleSupply, "market.idleSupply");
    }

    function testIncreaseIdleWhenSupplyGapIsSmaller(Types.Market memory _market, uint256 amount, uint256 supplyGap)
        public
    {
        TestMarket storage testMarket = testMarkets[dai];
        supplyGap = _setSupplyGap(testMarket, bound(supplyGap, (10 ** testMarket.decimals), testMarket.maxAmount));

        _market.aToken = testMarket.aToken;
        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);

        market = _market;

        amount = bound(amount, supplyGap + 10, testMarket.maxAmount);
        uint256 expectedIdleIncrease = amount - supplyGap;

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        // Cannot check data in this case because there can be a rounding error in the idle supply by 1. See note below.
        vm.expectEmit(true, true, true, false);
        emit Events.IdleSupplyUpdated(testMarket.underlying, _market.idleSupply + expectedIdleIncrease);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);

        assertGt(idleSupplyIncrease, 0, "idleSupplyIncrease is zero");

        // Note: Max rounding error should be 1 from the difference in supply gap calculations from an extra rayMul.
        assertApproxEqAbs(suppliable, supplyGap, 1, "suppliable");
        assertApproxEqAbs(idleSupplyIncrease, expectedIdleIncrease, 1, "idleSupplyIncrease");
        assertApproxEqAbs(market.idleSupply, _market.idleSupply + expectedIdleIncrease, 1, "market.idleSupply");
    }

    function testDecreaseIdle(Types.Market memory _market, uint256 amount) public {
        TestMarket storage testMarket = testMarkets[dai];
        amount = bound(amount, testMarket.minAmount, testMarket.maxAmount);

        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);
        market = _market;

        uint256 expectedIdleDecrease = Math.min(_market.idleSupply, amount);

        if (_market.idleSupply != 0 && amount != 0) {
            vm.expectEmit(true, true, true, true);
            emit Events.IdleSupplyUpdated(testMarket.underlying, _market.idleSupply - expectedIdleDecrease);
        }

        (uint256 amountToProcess, uint256 idleDecrease) = market.decreaseIdle(dai, amount);

        assertEq(amountToProcess, amount - expectedIdleDecrease, "toProcess");
        assertEq(idleDecrease, expectedIdleDecrease, "matchedIdle");
        assertEq(market.idleSupply, _market.idleSupply - expectedIdleDecrease, "market.idleSupply");
    }
}
