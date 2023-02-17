// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

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

    function testIncreaseIdleWhenSupplyGapIsLarger(Types.Market memory _market, uint256 amount, uint256 supplyCap)
        public
    {
        TestMarket storage testMarket = testMarkets[dai];
        supplyCap = _boundSupplyCapExceeded(
            testMarket,
            (testMarket.totalSupply() + _accruedToTreasury(testMarket.underlying) / (10 ** testMarket.decimals)) + 1,
            ReserveConfiguration.MAX_VALID_SUPPLY_CAP
        );

        _market.aToken = testMarket.aToken;
        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);

        market = _market;

        _setSupplyCap(testMarket, supplyCap);

        uint256 supplyGap = _supplyGap(testMarket);
        amount = bound(amount, testMarket.minAmount, supplyGap);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);

        assertEq(suppliable, amount, "suppliable");
        assertEq(idleSupplyIncrease, 0, "idleSupplyIncrease");
        assertEq(market.idleSupply, _market.idleSupply, "market.idleSupply");
    }

    function testIncreaseIdleWhenSupplyGapIsSmaller(Types.Market memory _market, uint256 amount, uint256 supplyCap)
        public
    {
        TestMarket storage testMarket = testMarkets[dai];
        supplyCap = _boundSupplyCapExceeded(testMarket, testMarket.minAmount * 10, supplyCap);

        _market.aToken = testMarket.aToken;
        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);

        market = _market;

        _setSupplyCap(testMarket, supplyCap);

        uint256 supplyGap = _supplyGap(testMarket);

        amount = bound(amount, supplyGap, testMarket.maxAmount);
        uint256 expectedIdleIncrease = amount - supplyGap;

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        vm.expectEmit(true, true, true, true);
        emit Events.IdleSupplyUpdated(testMarket.underlying, _market.idleSupply + expectedIdleIncrease);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);

        assertEq(suppliable, supplyGap, "suppliable");
        assertEq(idleSupplyIncrease, expectedIdleIncrease, "idleSupplyIncrease");
        assertEq(market.idleSupply, _market.idleSupply + expectedIdleIncrease, "market.idleSupply");
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
