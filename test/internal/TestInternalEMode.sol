pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import "test/helpers/ForkTest.sol";
import "src/MorphoInternal.sol";
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";
import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";
/// Assumption : Unit Test made for only one E-mode

contract TestInternalEMode is ForkTest, PositionsManagerInternal {
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
    uint256 internal constant BORROWING_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFF;
    uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    uint256 internal constant BORROWING_ENABLED_START_BIT_POSITION = 58;
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
        market.stableDebtToken = reserveData.stableDebtTokenAddress;
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

    function testIsInEModeCategory() public {
        address underlying;
        underlying = address(uint160(bound(uint256(uint160(underlying)), 1, type(uint160).max)));
        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);

        address priceSourceEMode = address(1);
        uint16 ltv = uint16(PercentageMath.PERCENTAGE_FACTOR - 30);
        uint16 lt = uint16(PercentageMath.PERCENTAGE_FACTOR - 20);
        uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);

        uint8 EModeCategoryId;
        EModeCategoryId = uint8(bound(uint256(EModeCategoryId), 0, type(uint8).max));

        if (EModeCategoryId != 0) {
            vm.prank(address(poolAdmin));
            poolConfigurator.setEModeCategory(EModeCategoryId, ltv, lt, liquidationBonus, priceSourceEMode, "");

            vm.prank(address(poolAdmin));
            poolConfigurator.setAssetEModeCategory(underlying, EModeCategoryId);
        }

        bool expectedIsInEMode = _E_MODE_CATEGORY_ID == EModeCategoryId && _E_MODE_CATEGORY_ID != 0 ? true : false;
        bool isInEMode = _isInEModeCategory(config);

        assertEq(expectedIsInEMode, isInEMode, "Wrong E-Mode");
    }

    function testGetAssetPrice() public {
        address underlying;
        underlying = address(uint160(bound(uint256(uint160(underlying)), 1, type(uint160).max)));

        address priceSourceEMode;
        priceSourceEMode = address(
            uint160(bound(uint256(uint160(priceSourceEMode)), uint256(uint160(underlying)) + 1, type(uint160).max))
        );

        vm.assume(underlying != priceSourceEMode);

        uint256 underlyingPriceEMode;
        underlyingPriceEMode = bound(underlyingPriceEMode, 0, type(uint256).max);
        uint256 underlyingPrice;
        underlyingPrice = bound(underlyingPrice, 0, type(uint256).max);

        oracle.setAssetPrice(underlying, underlyingPrice);
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);

        bool isInEMode;
        uint256 randomNumber;
        randomNumber = bound(randomNumber, 0, type(uint256).max);
        isInEMode = randomNumber % 2 == 0;

        uint256 expectedPrice = isInEMode && underlyingPriceEMode != 0 ? underlyingPriceEMode : underlyingPrice;
        uint256 realPrice = _getAssetPrice(underlying, oracle, isInEMode, priceSourceEMode);

        assertEq(expectedPrice, realPrice, "Wrong price");
    }

    function testAuthorizeBorrowEmode() public {
        address priceSourceEMode = address(1);
        uint16 ltv = uint16(PercentageMath.PERCENTAGE_FACTOR - 20);
        uint16 lt = uint16(PercentageMath.PERCENTAGE_FACTOR - 10);
        uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);

        uint8 EModeCategoryId;
        EModeCategoryId = uint8(bound(uint256(EModeCategoryId), 1, type(uint8).max));

        if (EModeCategoryId != 0) {
            vm.prank(address(poolAdmin));
            poolConfigurator.setEModeCategory(EModeCategoryId, ltv, lt, liquidationBonus, priceSourceEMode, "");
            console.log("true");
            vm.prank(address(poolAdmin));
            poolConfigurator.setAssetEModeCategory(dai, EModeCategoryId);
        }

        Types.Indexes256 memory indexes;
        uint256 poolSupplyIndex;
        uint256 p2pSupplyIndex;
        uint256 poolBorrowIndex;
        uint256 p2pBorrowIndex;

        poolSupplyIndex = bound(poolSupplyIndex, 0, type(uint96).max);
        p2pSupplyIndex = bound(p2pSupplyIndex, 0, type(uint96).max);
        poolBorrowIndex = bound(poolBorrowIndex, 0, type(uint96).max);
        p2pBorrowIndex = bound(p2pBorrowIndex, 0, type(uint96).max);

        indexes.borrow.poolIndex = poolBorrowIndex;
        indexes.borrow.p2pIndex = p2pBorrowIndex;
        indexes.supply.poolIndex = poolSupplyIndex;
        indexes.supply.p2pIndex = p2pSupplyIndex;

        if (_E_MODE_CATEGORY_ID != 0 && _E_MODE_CATEGORY_ID != EModeCategoryId) {
            vm.expectRevert(abi.encodeWithSelector(Errors.InconsistentEMode.selector));
        }
        this.authorizeBorrow(dai, 0, indexes);
    }

    function authorizeBorrow(address underlying, uint256 amount, Types.Indexes256 memory indexes) external view {
        _authorizeBorrow(underlying, amount, indexes);
    }
}
