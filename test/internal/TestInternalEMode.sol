pragma solidity ^0.8.0;

import "test/helpers/ForkTest.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {Morpho} from "src/Morpho.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";
import {PriceOracleSentinelMock} from "test/mocks/PriceOracleSentinelMock.sol";
import {AaveOracleMock} from "test/mocks/AaveOracleMock.sol";
import {PoolAdminMock} from "test/mocks/PoolAdminMock.sol";
import "src/MorphoInternal.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

/// Assumption : Unit Test made for only one E-mode
contract TestInternalEMode is ForkTest, MorphoInternal {
    using MarketLib for Types.Market;
    using PoolLib for IPool;
    using MarketBalanceLib for Types.MarketBalances;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using Math for uint256;
    using TestConfigLib for TestConfig;
    using SafeTransferLib for ERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant LIQUIDATION_THRESHOLD_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF;
    uint256 internal constant LTV_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;
    uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    IMorpho internal morpho;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    constructor() MorphoStorage(_initConfig().getAddressesProvider(), uint8(vm.envUint("E_MODE_CATEGORY_ID"))) {}

    function setUp() public virtual override {
        super.setUp();

        _defaultIterations = Types.Iterations(10, 10);

        createTestMarket(dai, 0, 3_333);
        createTestMarket(wbtc, 0, 3_333);
        createTestMarket(usdc, 0, 3_333);
        createTestMarket(wNative, 0, 3_333);

        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);
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

    function testInitializeEMode() public {
        uint256 eModeCategoryId = vm.envUint("E_MODE_CATEGORY_ID");
        assertEqUint(_E_MODE_CATEGORY_ID, eModeCategoryId);
    }

    function testLtvLiquidationThresholdPriceSourceEMode() public {
        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(reserves[i]);
            if (_E_MODE_CATEGORY_ID == currentConfig.getEModeCategory()) {
                vm.prank(address(poolAdmin));
                currentConfig.setEModeCategory(_E_MODE_CATEGORY_ID + 1);
            }
        }
        DataTypes.ReserveData memory reserveData = _POOL.getReserveData(dai);

        DataTypes.ReserveConfigurationMap memory config = reserveData.configuration;

        uint16 ltConfig =
            uint16((config.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION);
        uint16 ltvConfig = uint16(config.data & ~LTV_MASK);

        uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);

        uint16 ltvEMode;
        uint16 ltEMode;
        ltEMode = uint16(bound(ltEMode, ltConfig + 1, type(uint16).max));
        ltvEMode = uint16(bound(ltvEMode, ltvConfig + 1, ltEMode));

        uint256 underlyingPrice;
        uint256 underlyingPriceEMode;
        underlyingPrice = bound(underlyingPrice, 1, type(uint96).max - 1);
        underlyingPriceEMode = bound(underlyingPriceEMode, underlyingPrice + 1, type(uint96).max);
        vm.assume(uint256(ltEMode).percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(underlyingPrice != underlyingPriceEMode);

        address priceSourceEMode = address(1);

        DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
            ltv: ltvEMode,
            liquidationThreshold: ltEMode,
            liquidationBonus: liquidationBonus,
            priceSource: priceSourceEMode,
            label: ""
        });
        if (_E_MODE_CATEGORY_ID != 0) {
            vm.prank(address(poolAdmin));
            poolConfigurator.setEModeCategory(
                _E_MODE_CATEGORY_ID, ltvEMode, ltEMode, liquidationBonus, priceSourceEMode, ""
            );

            vm.prank(address(poolAdmin));
            poolConfigurator.setAssetEModeCategory(dai, _E_MODE_CATEGORY_ID);
        }
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);
        oracle.setAssetPrice(dai, underlyingPrice);

        Types.LiquidityVars memory vars;
        vars.oracle = oracle;
        vars.user = address(this);
        vars.eModeCategory = eModeCategory;
        (uint256 underlyingPriceAsset, uint256 ltv, uint256 lt,) = _assetLiquidityData(dai, vars);

        assertEq(uint16(ltv), _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? ltvEMode : ltvConfig, "Loan to value E-mode");
        assertEq(
            uint16(lt), _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? ltEMode : ltConfig, "Liquidation Threshold E-Mode"
        );
        assertEq(
            underlyingPriceAsset,
            _E_MODE_CATEGORY_ID != 0 ? underlyingPriceEMode : underlyingPrice,
            "Underlying Price E-Mode"
        );
    }

    // struct TestSeizeVars1 {
    //     address priceSourceEMode;
    //     uint256 liquidationBonus;
    //     uint256 collateralTokenUnit;
    //     uint256 borrowTokenUnit;
    //     uint256 borrowPrice;
    //     uint256 collateralPrice;
    // }

    // struct TestSeizeVars2 {
    //     uint256 amountToSeize;
    //     uint256 amountToLiquidate;
    // }

    // function testCalculateAmountToSeizeEMode(
    //     uint256 maxToLiquidate,
    //     uint256 collateralAmount
    // ) public {
    //     maxToLiquidate = bound(maxToLiquidate, 0, 1_000_000 ether);
    //     collateralAmount = bound(collateralAmount, 0, 1_000_000 ether);
    //     (, Types.Indexes256 memory indexes) = _computeIndexes(dai);
    //     TestSeizeVars1 memory vars;

    //     _marketBalances[dai].collateral[address(1)] = collateralAmount.rayDivUp(
    //         indexes.supply.poolIndex
    //     );

    //     DataTypes.ReserveConfigurationMap memory config = _POOL
    //         .getConfiguration(dai);
    //     (, , vars.liquidationBonus, vars.collateralTokenUnit, , ) = config
    //         .getParams();
    //     if (
    //         _E_MODE_CATEGORY_ID != 0 &&
    //         _E_MODE_CATEGORY_ID == config.getEModeCategory()
    //     ) {
    //         DataTypes.EModeCategory memory eModeCategory = _POOL
    //             .getEModeCategoryData(_E_MODE_CATEGORY_ID);
    //         vars.liquidationBonus = eModeCategory.liquidationBonus;
    //         vars.priceSourceEMode = eModeCategory.priceSource;
    //     }
    //     (, , , vars.borrowTokenUnit, , ) = _POOL
    //         .getConfiguration(wbtc)
    //         .getParams();

    //     vars.collateralTokenUnit = 10**vars.collateralTokenUnit;
    //     vars.borrowTokenUnit = 10**vars.borrowTokenUnit;
    //     oracle.setAssetPrice(vars.priceSourceEMode, 2);
    //     oracle.setAssetPrice(dai, 1);

    //     vars.borrowPrice = oracle.getAssetPrice(usdc);
    //     vars.collateralPrice = oracle.getAssetPrice(dai);

    //     TestSeizeVars2 memory expected;
    //     TestSeizeVars2 memory actual;

    //     expected.amountToSeize = Math.min(
    //         ((maxToLiquidate * vars.borrowPrice * vars.collateralTokenUnit) /
    //             (vars.borrowTokenUnit * vars.collateralPrice)).percentMul(
    //                 vars.liquidationBonus
    //             ),
    //         collateralAmount
    //     );
    //     expected.amountToLiquidate = Math.min(
    //         maxToLiquidate,
    //         ((collateralAmount * vars.collateralPrice * vars.borrowTokenUnit) /
    //             (vars.borrowPrice * vars.collateralTokenUnit)).percentDiv(
    //                 vars.liquidationBonus
    //             )
    //     );

    //     (
    //         actual.amountToLiquidate,
    //         actual.amountToSeize
    //     ) = _calculateAmountToSeize(
    //         wbtc,
    //         dai,
    //         maxToLiquidate,
    //         address(1),
    //         indexes.supply.poolIndex
    //     );

    //     assertApproxEqAbs(
    //         actual.amountToSeize,
    //         expected.amountToSeize,
    //         1,
    //         "amount to seize not equal"
    //     );
    //     assertApproxEqAbs(
    //         actual.amountToLiquidate,
    //         expected.amountToLiquidate,
    //         1,
    //         "amount to liquidate not equal"
    //     );
    // }
}
