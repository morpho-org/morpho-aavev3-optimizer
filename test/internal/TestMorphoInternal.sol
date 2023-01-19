// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPriceOracleGetter} from "@aave-v3-core/interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {MorphoInternal, MorphoStorage} from "src/MorphoInternal.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "src/libraries/MarketBalanceLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import "test/helpers/InternalTest.sol";

contract TestMorphoInternal is InternalTest, MorphoInternal {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using PoolLib for IPool;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    IPriceOracleGetter internal oracle;

    function setUp() public virtual override {
        super.setUp();

        _defaultMaxLoops = Types.MaxLoops(10, 10);

        createTestMarket(dai, 0, 3_333);
        createTestMarket(wbtc, 0, 3_333);
        createTestMarket(usdc, 0, 3_333);
        createTestMarket(usdt, 0, 3_333);
        createTestMarket(wNative, 0, 3_333);

        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(usdt).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(usdt, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);

        oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
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
        (, Types.Indexes256 memory indexes2) = _computeIndexes(underlying);

        assertEq(indexes1.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertEq(indexes1.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertEq(indexes1.supply.poolIndex, indexes2.supply.poolIndex);
        assertEq(indexes1.borrow.poolIndex, indexes2.borrow.poolIndex);

        vm.warp(block.timestamp + 20);

        (, Types.Indexes256 memory indexes3) = _computeIndexes(underlying);

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

    function testUpdateInDS(address user, uint96 onPool, uint96 inP2P, bool head) public {
        vm.assume(user != address(0));
        vm.assume(onPool != 0);
        vm.assume(inP2P != 0);

        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateInDS(address(0), user, marketBalances.poolSuppliers, marketBalances.p2pSuppliers, onPool, inP2P, head);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateSupplierInDS(address user, uint96 onPool, uint96 inP2P, bool head) public {
        vm.assume(user != address(0));
        vm.assume(onPool != 0);
        vm.assume(inP2P != 0);

        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateSupplierInDS(dai, user, onPool, inP2P, head);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateBorrowerInDS(address user, uint96 onPool, uint96 inP2P, bool head) public {
        vm.assume(user != address(0));
        vm.assume(onPool != 0);
        vm.assume(inP2P != 0);

        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateBorrowerInDS(dai, user, onPool, inP2P, head);
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
        _updateSupplierInDS(dai, user, onPool, inP2P, true);

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
        bool head,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex
    ) public {
        vm.assume(user != address(0));
        poolBorrowIndex = bound(poolBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pBorrowIndex = bound(p2pBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        _updateBorrowerInDS(dai, user, onPool, inP2P, head);

        uint256 balance =
            _getUserBorrowBalanceFromIndexes(dai, user, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex));

        assertEq(
            balance,
            _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex))
        );
    }

    function testAssetLiquidityData() public {
        _POOL.setUserUseReserveAsCollateral(dai, false);

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        (uint256 poolLtv, uint256 poolLt,, uint256 poolDecimals,,) = _POOL.getConfiguration(dai).getParams();
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);
        (uint256 price, uint256 ltv, uint256 lt, uint256 units) = _assetLiquidityData(dai, vars);

        assertEq(price, oracle.getAssetPrice(dai), "price not equal to oracle price 1");
        assertEq(ltv, 0, "ltv not equal to 0");
        assertEq(lt, 0, "lt not equal to 0");
        assertEq(units, 10 ** poolDecimals, "units not equal to pool decimals 1");

        _POOL.setUserUseReserveAsCollateral(dai, true);
        morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        vars.morphoPoolConfig = morphoPoolConfig;

        (price, ltv, lt, units) = _assetLiquidityData(dai, vars);

        assertGt(price, 0, "price not gt 0");
        assertGt(ltv, 0, "ltv not gt 0");
        assertGt(lt, 0, "lt not gt 0");
        assertGt(units, 0, "units not gt 0");

        assertEq(price, oracle.getAssetPrice(dai), "price not equal to oracle price 2");
        assertEq(ltv, poolLtv, "ltv not equal to pool ltv");
        assertEq(lt, poolLt, "lt not equal to pool lt");
        assertEq(units, 10 ** poolDecimals, "units not equal to pool decimals 2");
    }

    function testLiquidityDataCollateral(uint256 amount, uint256 amountWithdrawn) public {
        amount = bound(amount, 0, 1_000_000 ether);
        amountWithdrawn = bound(amountWithdrawn, 0, amount);

        _marketBalances[dai].collateral[address(1)] = amount.rayDivUp(_market[dai].indexes.supply.poolIndex);

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);

        (uint256 collateral, uint256 borrowable, uint256 maxDebt) = _collateralData(dai, vars, amountWithdrawn);

        (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit) =
            _assetLiquidityData(dai, vars);

        amountWithdrawn = bound(
            amountWithdrawn,
            0,
            _marketBalances[dai].scaledCollateralBalance(address(1)).rayMulDown(_market[dai].indexes.supply.poolIndex)
        );
        uint256 expectedCollateralValue = (
            _getUserCollateralBalanceFromIndex(dai, address(1), _market[dai].indexes.supply.poolIndex) - amountWithdrawn
        ) * underlyingPrice / tokenUnit;
        assertEq(collateral, expectedCollateralValue, "collateralValue not equal to expected");
        assertEq(borrowable, expectedCollateralValue.percentMulDown(ltv), "borrowable not equal to expected");
        assertEq(maxDebt, expectedCollateralValue.percentMulDown(liquidationThreshold), "maxDebt not equal to expected");
    }

    function testLiquidityDataDebt(uint256 amountPool, uint256 amountP2P, uint256 amountBorrowed) public {
        amountPool = bound(amountPool, 0, 1_000_000 ether);
        amountP2P = bound(amountP2P, 0, 1_000_000 ether);
        amountBorrowed = bound(amountBorrowed, 0, 1_000_000 ether);

        _updateBorrowerInDS(
            dai,
            address(1),
            amountPool.rayDiv(_market[dai].indexes.borrow.poolIndex),
            amountP2P.rayDiv(_market[dai].indexes.borrow.p2pIndex),
            true
        );

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);

        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        uint256 debt = _debt(dai, vars, amountBorrowed);

        (uint256 underlyingPrice,,, uint256 tokenUnit) = _assetLiquidityData(dai, vars);

        uint256 expectedDebtValue = (_getUserBorrowBalanceFromIndexes(dai, address(1), indexes.borrow) + amountBorrowed)
            * underlyingPrice / tokenUnit;
        assertApproxEqAbs(debt, expectedDebtValue, 1, "debtValue not equal to expected");
    }

    function testLiquidityDataAllCollaterals() public {
        _marketBalances[dai].collateral[address(1)] = uint256(100 ether).rayDivUp(_market[dai].indexes.supply.poolIndex);
        _marketBalances[wbtc].collateral[address(1)] = uint256(1e8).rayDivUp(_market[wbtc].indexes.supply.poolIndex);
        _marketBalances[usdc].collateral[address(1)] = uint256(1e8).rayDivUp(_market[usdc].indexes.supply.poolIndex);

        _userCollaterals[address(1)].add(dai);
        _userCollaterals[address(1)].add(wbtc);
        _userCollaterals[address(1)].add(usdc);

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);

        (uint256 collateral, uint256 borrowable, uint256 maxDebt) = _totalCollateralData(dai, vars, 10 ether);

        uint256[3] memory collateralSingles;
        uint256[3] memory borrowableSingles;
        uint256[3] memory maxDebtSingles;

        (collateralSingles[0], borrowableSingles[0], maxDebtSingles[0]) = _collateralData(dai, vars, 10 ether);
        (collateralSingles[1], borrowableSingles[1], maxDebtSingles[1]) = _collateralData(wbtc, vars, 0);
        (collateralSingles[2], borrowableSingles[2], maxDebtSingles[2]) = _collateralData(usdc, vars, 0);

        assertEq(
            collateral,
            collateralSingles[0] + collateralSingles[1] + collateralSingles[2],
            "collateral not equal to single"
        );
        assertEq(
            borrowable,
            borrowableSingles[0] + borrowableSingles[1] + borrowableSingles[2],
            "borrowable not equal to single"
        );
        assertEq(maxDebt, maxDebtSingles[0] + maxDebtSingles[1] + maxDebtSingles[2], "maxDebt not equal to single");
    }

    function testLiquidityDataAllDebts() public {
        _updateBorrowerInDS(
            dai,
            address(1),
            uint256(100 ether).rayDiv(_market[dai].indexes.borrow.poolIndex),
            uint256(100 ether).rayDiv(_market[dai].indexes.borrow.p2pIndex),
            true
        );
        _updateBorrowerInDS(
            wbtc,
            address(1),
            uint256(1e8).rayDiv(_market[wbtc].indexes.borrow.poolIndex),
            uint256(1e8).rayDiv(_market[wbtc].indexes.borrow.p2pIndex),
            true
        );
        _updateBorrowerInDS(
            usdc,
            address(1),
            uint256(1e8).rayDiv(_market[usdc].indexes.borrow.poolIndex),
            uint256(1e8).rayDiv(_market[usdc].indexes.borrow.p2pIndex),
            true
        );

        _userBorrows[address(1)].add(dai);
        _userBorrows[address(1)].add(wbtc);
        _userBorrows[address(1)].add(usdc);

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);
        uint256 debt = _totalDebt(dai, vars, 10 ether);

        uint256[3] memory debtSingles = [_debt(dai, vars, 10 ether), _debt(wbtc, vars, 0), _debt(usdc, vars, 0)];

        assertApproxEqAbs(
            debt, debtSingles[0] + debtSingles[1] + debtSingles[2], 1, "collateral not equal to sum of singles"
        );
    }

    function testLiquidityData() public {
        _marketBalances[dai].collateral[address(1)] = uint256(100 ether).rayDivUp(_market[dai].indexes.supply.poolIndex);
        _marketBalances[wbtc].collateral[address(1)] = uint256(1e8).rayDivUp(_market[wbtc].indexes.supply.poolIndex);
        _marketBalances[usdc].collateral[address(1)] = uint256(1e8).rayDivUp(_market[usdc].indexes.supply.poolIndex);

        _userCollaterals[address(1)].add(dai);
        _userCollaterals[address(1)].add(wbtc);
        _userCollaterals[address(1)].add(usdc);

        _updateBorrowerInDS(
            dai,
            address(1),
            uint256(100 ether).rayDiv(_market[dai].indexes.borrow.poolIndex),
            uint256(100 ether).rayDiv(_market[dai].indexes.borrow.p2pIndex),
            true
        );
        _updateBorrowerInDS(
            wbtc,
            address(1),
            uint256(1e8).rayDiv(_market[wbtc].indexes.borrow.poolIndex),
            uint256(1e8).rayDiv(_market[wbtc].indexes.borrow.p2pIndex),
            true
        );
        _updateBorrowerInDS(
            usdc,
            address(1),
            uint256(1e8).rayDiv(_market[usdc].indexes.borrow.poolIndex),
            uint256(1e8).rayDiv(_market[usdc].indexes.borrow.p2pIndex),
            true
        );

        _userBorrows[address(1)].add(dai);
        _userBorrows[address(1)].add(wbtc);
        _userBorrows[address(1)].add(usdc);

        DataTypes.UserConfigurationMap memory morphoPoolConfig = _POOL.getUserConfiguration(address(this));

        Types.LiquidityData memory liquidityData = _liquidityData(dai, address(1), 10 ether, 10 ether);
        DataTypes.EModeCategory memory eModeCategory = _POOL.getEModeCategoryData(0);
        Types.LiquidityVars memory vars = Types.LiquidityVars(address(1), oracle, eModeCategory, morphoPoolConfig);

        (uint256 collateral, uint256 borrowable, uint256 maxDebt) = _totalCollateralData(dai, vars, 10 ether);
        uint256 debt = _totalDebt(dai, vars, 10 ether);

        assertEq(liquidityData.collateral, collateral, "collateral not equal");
        assertEq(liquidityData.borrowable, borrowable, "borrowable not equal");
        assertEq(liquidityData.maxDebt, maxDebt, "maxDebt not equal");
        assertEq(liquidityData.debt, debt, "debt not equal");
    }

    function testGetUserHealthFactor(
        uint256 collateral,
        uint256 amountPool,
        uint256 amountP2P,
        uint256 amountWithdrawn,
        bool head
    ) public {
        collateral = bound(collateral, 0, 1_000_000 ether);
        amountPool = bound(amountPool, 1, 1_000_000 ether);
        amountP2P = bound(amountP2P, 1, 1_000_000 ether);
        amountWithdrawn = bound(amountWithdrawn, 0, collateral);

        _marketBalances[dai].collateral[address(1)] = collateral.rayDivUp(_market[dai].indexes.supply.poolIndex);
        _userCollaterals[address(1)].add(dai);

        assertEq(
            _getUserHealthFactor(dai, address(1), amountWithdrawn),
            type(uint256).max,
            "health factor not equal to uint max"
        );

        _userBorrows[address(1)].add(dai);
        _updateBorrowerInDS(
            dai,
            address(1),
            amountPool.rayDiv(_market[dai].indexes.borrow.poolIndex),
            amountP2P.rayDiv(_market[dai].indexes.borrow.p2pIndex),
            head
        );

        Types.LiquidityData memory liquidityData = _liquidityData(dai, address(1), amountWithdrawn, 0);

        assertEq(
            _getUserHealthFactor(dai, address(1), amountWithdrawn),
            liquidityData.maxDebt.wadDiv(liquidityData.debt),
            "health factor not expected"
        );
    }

    function testSetPauseStatus() public {
        for (uint256 marketIndex; marketIndex < testMarkets.length; ++marketIndex) {
            _revert();

            address underlying = testMarkets[marketIndex];

            Types.PauseStatuses storage pauseStatuses = _market[underlying].pauseStatuses;

            assertFalse(pauseStatuses.isSupplyPaused);
            assertFalse(pauseStatuses.isBorrowPaused);
            assertFalse(pauseStatuses.isRepayPaused);
            assertFalse(pauseStatuses.isWithdrawPaused);
            assertFalse(pauseStatuses.isLiquidateCollateralPaused);
            assertFalse(pauseStatuses.isLiquidateBorrowPaused);

            _setPauseStatus(underlying, true);

            assertTrue(pauseStatuses.isSupplyPaused);
            assertTrue(pauseStatuses.isBorrowPaused);
            assertTrue(pauseStatuses.isRepayPaused);
            assertTrue(pauseStatuses.isWithdrawPaused);
            assertTrue(pauseStatuses.isLiquidateCollateralPaused);
            assertTrue(pauseStatuses.isLiquidateBorrowPaused);
        }
    }

    function testApproveManager(address owner, address manager, bool isAllowed) public {
        _approveManager(owner, manager, isAllowed);
        assertEq(_isManaging[owner][manager], isAllowed);
    }

    struct TestSeizeVars1 {
        uint256 liquidationBonus;
        uint256 collateralTokenUnit;
        uint256 borrowTokenUnit;
        uint256 borrowPrice;
        uint256 collateralPrice;
    }

    struct TestSeizeVars2 {
        uint256 amountToSeize;
        uint256 amountToLiquidate;
    }

    function testCalculateAmountToSeize(uint256 maxToLiquidate, uint256 collateralAmount) public {
        maxToLiquidate = bound(maxToLiquidate, 0, 1_000_000 ether);
        collateralAmount = bound(collateralAmount, 0, 1_000_000 ether);
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);
        TestSeizeVars1 memory vars;

        _marketBalances[dai].collateral[address(1)] = collateralAmount.rayDivUp(indexes.supply.poolIndex);

        (,, vars.liquidationBonus, vars.collateralTokenUnit,,) = _POOL.getConfiguration(dai).getParams();
        (,,, vars.borrowTokenUnit,,) = _POOL.getConfiguration(wbtc).getParams();

        vars.collateralTokenUnit = 10 ** vars.collateralTokenUnit;
        vars.borrowTokenUnit = 10 ** vars.borrowTokenUnit;

        vars.borrowPrice = oracle.getAssetPrice(wbtc);
        vars.collateralPrice = oracle.getAssetPrice(dai);

        TestSeizeVars2 memory expected;
        TestSeizeVars2 memory actual;

        expected.amountToSeize = Math.min(
            (
                (maxToLiquidate * vars.borrowPrice * vars.collateralTokenUnit)
                    / (vars.borrowTokenUnit * vars.collateralPrice)
            ).percentMul(vars.liquidationBonus),
            collateralAmount
        );
        expected.amountToLiquidate = Math.min(
            maxToLiquidate,
            (
                (collateralAmount * vars.collateralPrice * vars.borrowTokenUnit)
                    / (vars.borrowPrice * vars.collateralTokenUnit)
            ).percentDiv(vars.liquidationBonus)
        );

        (actual.amountToLiquidate, actual.amountToSeize) =
            _calculateAmountToSeize(wbtc, dai, maxToLiquidate, address(1), indexes.supply.poolIndex);

        assertApproxEqAbs(actual.amountToSeize, expected.amountToSeize, 1, "amount to seize not equal");
        assertApproxEqAbs(actual.amountToLiquidate, expected.amountToLiquidate, 1, "amount to liquidate not equal");
    }
}
