// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {TestConfig} from "./helpers/TestConfig.sol";

import {TestSetup} from "./setup/TestSetup.sol";
import {console2} from "@forge-std/console2.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "../src/libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "../src/libraries/aave/ReserveConfiguration.sol";

import {MorphoInternal, MorphoStorage} from "../src/MorphoInternal.sol";
import {Types} from "../src/libraries/Types.sol";
import {MarketLib} from "../src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "../src/libraries/MarketBalanceLib.sol";
import {PoolLib} from "../src/libraries/PoolLib.sol";

contract TestMorphoInternal is TestSetup, MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using PoolLib for IPool;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using TestConfig for TestConfig.Config;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    constructor() TestSetup() MorphoStorage(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function setUp() public virtual override {
        _defaultMaxLoops = Types.MaxLoops(10, 10, 10, 10);
        _maxSortedUsers = 20;

        createTestMarket(dai, 0, 3_333);
    }

    function createTestMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        DataTypes.ReserveData memory reserveData = _POOL.getReserveData(underlying);

        Types.Market storage market = _market[underlying];

        Types.Indexes256 memory indexes;
        indexes.supply.p2pIndex = WadRayMath.RAY;
        indexes.borrow.p2pIndex = WadRayMath.RAY;
        (indexes.supply.poolIndex, indexes.borrow.poolIndex) = _POOL.getCurrentPoolIndexes(underlying);

        market.setIndexes(indexes);
        market.lastUpdateTimestamp = uint32(block.timestamp);

        market.underlying = underlying;
        market.aToken = reserveData.aTokenAddress;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(underlying);

        ERC20(underlying).safeApprove(address(_POOL), type(uint256).max);
    }

    // More detailed index tests to be in InterestRatesLib tests
    function testComputeIndexes() public {
        address underlying = dai;
        Types.Indexes256 memory indexes1 = _market[underlying].getIndexes();
        Types.Indexes256 memory indexes2 = _computeIndexes(underlying);

        assertEq(indexes1.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertEq(indexes1.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertEq(indexes1.supply.poolIndex, indexes2.supply.poolIndex);
        assertEq(indexes1.borrow.poolIndex, indexes2.borrow.poolIndex);

        vm.warp(block.timestamp + 20);

        Types.Indexes256 memory indexes3 = _computeIndexes(underlying);

        assertGt(indexes3.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertGt(indexes3.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertGt(indexes3.supply.poolIndex, indexes2.supply.poolIndex);
        assertGt(indexes3.borrow.poolIndex, indexes2.borrow.poolIndex);
    }

    function testUpdateIndexes() public {
        address underlying = dai;
        Types.Indexes256 memory indexes1 = _market[underlying].getIndexes();
        _updateIndexes(underlying);
        Types.Indexes256 memory indexes2 = _market[underlying].getIndexes();

        assertEq(indexes1.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertEq(indexes1.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertEq(indexes1.supply.poolIndex, indexes2.supply.poolIndex);
        assertEq(indexes1.borrow.poolIndex, indexes2.borrow.poolIndex);

        vm.warp(block.timestamp + 20);

        _updateIndexes(underlying);
        Types.Indexes256 memory indexes3 = _market[underlying].getIndexes();

        assertGt(indexes3.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertGt(indexes3.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertGt(indexes3.supply.poolIndex, indexes2.supply.poolIndex);
        assertGt(indexes3.borrow.poolIndex, indexes2.borrow.poolIndex);
    }

    function testUpdateInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateInDS(address(0), user, marketBalances.poolSuppliers, marketBalances.p2pSuppliers, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateSupplierInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateSupplierInDS(dai, user, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateBorrowerInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateBorrowerInDS(dai, user, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), 0);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), 0);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), onPool);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), inP2P);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testGetUserBalanceFromIndexes(uint96 onPool, uint96 inP2P, uint256 poolIndex, uint256 p2pIndex) public {
        poolIndex = bound(poolIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pIndex = bound(p2pIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);

        uint256 balance = _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolIndex, p2pIndex));

        assertEq(balance, uint256(onPool).rayMul(poolIndex) + uint256(inP2P).rayMul(p2pIndex));
    }

    function testGetUserSupplyBalanceFromIndexes(
        address user,
        uint96 onPool,
        uint96 inP2P,
        uint256 poolSupplyIndex,
        uint256 p2pSupplyIndex
    ) public {
        vm.assume(user != address(0));
        poolSupplyIndex = bound(poolSupplyIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pSupplyIndex = bound(p2pSupplyIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        _updateSupplierInDS(dai, user, onPool, inP2P);

        uint256 balance =
            _getUserSupplyBalanceFromIndexes(dai, user, Types.MarketSideIndexes256(poolSupplyIndex, p2pSupplyIndex));

        assertEq(
            balance,
            _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolSupplyIndex, p2pSupplyIndex))
        );
    }

    function testGetUserBorrowBalanceFromIndexes(
        address user,
        uint96 onPool,
        uint96 inP2P,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex
    ) public {
        vm.assume(user != address(0));
        poolBorrowIndex = bound(poolBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pBorrowIndex = bound(p2pBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        _updateBorrowerInDS(dai, user, onPool, inP2P);

        uint256 balance =
            _getUserBorrowBalanceFromIndexes(dai, user, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex));

        assertEq(
            balance,
            _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex))
        );
    }

    function testAssetLiquidityData() public {
        IPriceOracleGetter oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        (uint256 poolLtv, uint256 poolLt,, uint256 poolDecimals,,) = _POOL.getConfiguration(dai).getParams();

        (uint256 price, uint256 ltv, uint256 lt, uint256 units) = _assetLiquidityData(dai, oracle, morphoPoolConfig);
        assertEq(price, oracle.getAssetPrice(dai), "price not equal to oracle price 1");
        assertEq(ltv, 0, "ltv not equal to 0");
        assertEq(lt, 0, "lt not equal to 0");
        assertEq(units, 10 ** poolDecimals, "units not equal to pool decimals 1");

        fillBalance(address(this), type(uint256).max);
        ERC20(dai).approve(address(_POOL), type(uint256).max);
        _POOL.supplyToPool(dai, 100 ether);

        morphoPoolConfig = _POOL.getUserConfiguration(address(this));

        (price, ltv, lt, units) = _assetLiquidityData(dai, oracle, morphoPoolConfig);
        assertEq(price, oracle.getAssetPrice(dai), "price not equal to oracle price 2");
        assertEq(ltv, poolLtv, "ltv not equal to pool ltv");
        assertEq(lt, poolLt, "lt not equal to pool lt");
        assertEq(units, 10 ** poolDecimals, "units not equal to pool decimals 2");

        assertGt(price, 0, "price not gt 0");
        assertGt(ltv, 0, "ltv not gt 0");
        assertGt(lt, 0, "lt not gt 0");
        assertGt(units, 0, "units not gt 0");
    }

    function testLiquidityDataCollateral(uint256 amount, uint256 amountWithdrawn) public {
        amount = bound(amount, 0, 1_000_000 ether);
        amountWithdrawn = bound(amountWithdrawn, 0, amount);

        _marketBalances[dai].collateral[address(1)] = amount.rayDivUp(_market[dai].indexes.supply.poolIndex);

        fillBalance(address(this), type(uint256).max);
        ERC20(dai).approve(address(_POOL), type(uint256).max);
        _POOL.supplyToPool(dai, 100 ether);
        IPriceOracleGetter oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));

        Types.LiquidityData memory liquidityData =
            _liquidityDataCollateral(dai, address(1), oracle, morphoPoolConfig, amountWithdrawn);

        (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit) =
            _assetLiquidityData(dai, oracle, morphoPoolConfig);

        amountWithdrawn = bound(
            amountWithdrawn,
            0,
            _marketBalances[dai].scaledCollateralBalance(address(1)).rayMulDown(_market[dai].indexes.supply.poolIndex)
        );
        uint256 expectedCollateralValue = (
            _getUserCollateralBalanceFromIndex(dai, address(1), _market[dai].indexes.supply.poolIndex) - amountWithdrawn
        ) * underlyingPrice / tokenUnit;
        assertEq(liquidityData.collateral, expectedCollateralValue, "collateralValue not equal to expected");
        assertEq(
            liquidityData.borrowable, expectedCollateralValue.percentMulDown(ltv), "borrowable not equal to expected"
        );
        assertEq(
            liquidityData.maxDebt,
            expectedCollateralValue.percentMulDown(liquidationThreshold),
            "maxDebt not equal to expected"
        );
    }

    function testLiquidityDataDebt(uint256 amountPool, uint256 amountP2P, uint256 amountBorrowed) public {
        amountPool = bound(amountPool, 0, 1_000_000 ether);
        amountP2P = bound(amountP2P, 0, 1_000_000 ether);
        amountBorrowed = bound(amountBorrowed, 0, 1_000_000 ether);

        _updateBorrowerInDS(
            dai,
            address(1),
            amountPool.rayDiv(_market[dai].indexes.borrow.poolIndex),
            amountP2P.rayDiv(_market[dai].indexes.borrow.p2pIndex)
        );

        fillBalance(address(this), type(uint256).max);
        ERC20(dai).approve(address(_POOL), type(uint256).max);
        _POOL.supplyToPool(dai, 100 ether);
        IPriceOracleGetter oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        uint256 debt = _liquidityDataDebt(dai, address(1), oracle, morphoPoolConfig, amountBorrowed);

        (uint256 underlyingPrice,,, uint256 tokenUnit) = _assetLiquidityData(dai, oracle, morphoPoolConfig);

        uint256 expectedDebtValue = (_getUserBorrowBalanceFromIndexes(dai, address(1), indexes.borrow) + amountBorrowed)
            * underlyingPrice / tokenUnit;
        assertApproxEqAbs(debt, expectedDebtValue, 1, "debtValue not equal to expected");
    }

    /// TESTS TO ADD:

    // _liquidityDataAllCollaterals
    // _liquidityDataAllDebts
    // _liquidityData
    // _getUserHealthFactor

    // _setPauseStatus
}
