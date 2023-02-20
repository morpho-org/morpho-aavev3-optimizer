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

import "test/helpers/IntegrationTest.sol";
import "src/MorphoInternal.sol";
import "test/helpers/InternalTest.sol";
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";
import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";

contract TestInternalEMode is InternalTest, PositionsManagerInternal {
    using MarketLib for Types.Market;
    using PoolLib for IPool;
    using MarketBalanceLib for Types.MarketBalances;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using Math for uint256;
    using TestConfigLib for TestConfig;
    using SafeTransferLib for ERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function setUp() public virtual override {
        _defaultIterations = Types.Iterations(10, 10);
        _createMarket(dai, 0, 3_333);
        _createMarket(wbtc, 0, 3_333);
        _createMarket(usdc, 0, 3_333);
        _createMarket(wNative, 0, 3_333);

        _setBalances(address(this), type(uint256).max);

        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);
    }

    function testInitializeEMode() public {
        uint256 eModeCategoryId = vm.envOr("E_MODE_CATEGORY_ID", uint256(0));
        assertEq(_E_MODE_CATEGORY_ID, eModeCategoryId);
    }

    struct AssetData {
        uint256 underlyingPrice;
        uint256 underlyingPriceEMode;
        uint16 ltvEMode;
        uint16 ltEMode;
    }

    function testLtvLiquidationThresholdPriceSourceEMode(AssetData memory assetData) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            (uint16 ltvBound, uint16 ltBound, uint16 ltvConfig, uint16 ltConfig) =
                _getLtvLt(underlying, _E_MODE_CATEGORY_ID);

            assetData.ltEMode = uint16(bound(assetData.ltEMode, ltBound + 1, type(uint16).max));
            assetData.ltvEMode = uint16(bound(assetData.ltvEMode, ltvBound + 1, assetData.ltEMode));
            uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);
            assetData.underlyingPrice = bound(assetData.underlyingPrice, 0, type(uint96).max - 1);
            assetData.underlyingPriceEMode = bound(assetData.underlyingPriceEMode, 0, type(uint96).max);
            vm.assume(
                uint256(assetData.ltEMode).percentMul(uint256(liquidationBonus)) <= PercentageMath.PERCENTAGE_FACTOR
            );
            vm.assume(assetData.underlyingPrice != assetData.underlyingPriceEMode);

            DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
                ltv: assetData.ltvEMode,
                liquidationThreshold: assetData.ltEMode,
                liquidationBonus: liquidationBonus,
                priceSource: address(1),
                label: ""
            });
            if (_E_MODE_CATEGORY_ID != 0) {
                _setEModeCategoryAsset(eModeCategory, underlying, _E_MODE_CATEGORY_ID);
            }

            oracle.setAssetPrice(address(1), assetData.underlyingPriceEMode);
            oracle.setAssetPrice(underlying, assetData.underlyingPrice);

            Types.LiquidityVars memory vars;
            vars.oracle = oracle;
            vars.user = address(this);
            vars.eModeCategory = eModeCategory;
            (uint256 assetPrice, uint256 ltv, uint256 lt,) = _assetLiquidityData(underlying, vars);

            assertEq(
                uint16(ltv),
                _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? assetData.ltvEMode : ltvConfig,
                "Loan to value E-mode"
            );
            assertEq(
                uint16(lt),
                _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? assetData.ltEMode : ltConfig,
                "Liquidation Threshold E-Mode"
            );
            assertEq(
                assetPrice,
                _E_MODE_CATEGORY_ID != 0 && assetData.underlyingPriceEMode != 0
                    ? assetData.underlyingPriceEMode
                    : assetData.underlyingPrice,
                "Underlying Price E-Mode"
            );
        }
    }

    function testIsInEModeCategory(uint8 eModeCategoryId, uint16 lt, uint16 ltv, uint16 liquidationBonus) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            (uint16 ltvBound, uint16 ltBound,,) = _getLtvLt(underlying, eModeCategoryId);

            address priceSourceEMode = address(1);
            ltv = uint16(bound(ltv, ltvBound + 1, PercentageMath.PERCENTAGE_FACTOR - 1));
            lt = uint16(bound(lt, Math.max(ltv + 1, ltBound + 1), PercentageMath.PERCENTAGE_FACTOR));
            liquidationBonus = uint16(bound(liquidationBonus, PercentageMath.PERCENTAGE_FACTOR + 1, type(uint16).max));
            vm.assume(uint256(lt).percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR);

            eModeCategoryId = uint8(bound(uint256(eModeCategoryId), 1, type(uint8).max));

            DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
                ltv: ltv,
                liquidationThreshold: lt,
                liquidationBonus: liquidationBonus,
                priceSource: priceSourceEMode,
                label: ""
            });

            _setEModeCategoryAsset(eModeCategory, underlying, eModeCategoryId);

            DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);

            bool expectedIsInEMode = _E_MODE_CATEGORY_ID == eModeCategoryId && _E_MODE_CATEGORY_ID != 0;
            bool isInEMode = _isInEModeCategory(config);

            assertEq(isInEMode, expectedIsInEMode, "Wrong E-Mode");
        }
    }

    function testAssetPriceEMode(
        address underlying,
        address priceSourceEMode,
        uint256 underlyingPriceEMode,
        uint256 underlyingPrice
    ) public {
        priceSourceEMode = address(uint160(bound(uint256(uint160(priceSourceEMode)), 0, type(uint160).max)));
        vm.assume(underlying != priceSourceEMode);
        bool isInEMode = true;
        underlyingPriceEMode = bound(underlyingPriceEMode, 1, type(uint256).max);
        underlyingPrice = bound(underlyingPrice, 0, type(uint256).max);

        oracle.setAssetPrice(underlying, underlyingPrice);
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);

        uint256 expectedPrice = underlyingPriceEMode;
        uint256 realPrice = _getAssetPrice(underlying, oracle, isInEMode, priceSourceEMode);

        assertEq(expectedPrice, realPrice, "expectedPrice != realPrice");
    }

    function testAssetPriceNonEMode(
        address underlying,
        address priceSourceEMode,
        uint256 underlyingPriceEMode,
        uint256 underlyingPrice
    ) public {
        priceSourceEMode = address(uint160(bound(uint256(uint160(priceSourceEMode)), 0, type(uint160).max)));
        vm.assume(underlying != priceSourceEMode);
        bool isInEMode = false;
        underlyingPriceEMode = bound(underlyingPriceEMode, 1, type(uint256).max);
        underlyingPrice = bound(underlyingPrice, 0, type(uint256).max);

        oracle.setAssetPrice(underlying, underlyingPrice);
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);

        uint256 expectedPrice = underlyingPrice;
        uint256 realPrice = _getAssetPrice(underlying, oracle, isInEMode, priceSourceEMode);

        assertEq(expectedPrice, realPrice, "expectedPrice != realPrice");
    }

    function testAssetPriceEModeWithEModePriceZero(
        address underlying,
        address priceSourceEMode,
        uint256 underlyingPriceEMode,
        uint256 underlyingPrice
    ) public {
        priceSourceEMode = address(uint160(bound(uint256(uint160(priceSourceEMode)), 0, type(uint160).max)));
        vm.assume(underlying != priceSourceEMode);
        bool isInEMode = true;
        underlyingPriceEMode = 0;
        underlyingPrice = bound(underlyingPrice, 0, type(uint256).max);

        oracle.setAssetPrice(underlying, underlyingPrice);
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);

        uint256 expectedPrice = underlyingPrice;
        uint256 realPrice = _getAssetPrice(underlying, oracle, isInEMode, priceSourceEMode);

        assertEq(expectedPrice, realPrice, "expectedPrice != realPrice");
    }

    function testShouldNotAuthorizeBorrowInconsistentEmode(
        uint8 eModeCategoryId,
        Types.Indexes256 memory indexes,
        DataTypes.EModeCategory memory eModeCategory
    ) public {
        eModeCategoryId = uint8(bound(uint256(eModeCategoryId), 1, type(uint8).max));
        (uint16 ltvBound, uint16 ltBound,,) = _getLtvLt(dai, eModeCategoryId);
        eModeCategory.ltv = uint16(bound(eModeCategory.ltv, ltvBound + 1, PercentageMath.PERCENTAGE_FACTOR - 1));
        eModeCategory.liquidationThreshold = uint16(
            bound(
                eModeCategory.liquidationThreshold,
                Math.max(eModeCategory.ltv + 1, ltBound + 1),
                PercentageMath.PERCENTAGE_FACTOR
            )
        );

        eModeCategory.liquidationBonus = uint16(
            bound(
                eModeCategory.liquidationBonus,
                PercentageMath.PERCENTAGE_FACTOR + 1,
                2 * PercentageMath.PERCENTAGE_FACTOR
            )
        );

        vm.assume(
            uint256(eModeCategory.liquidationThreshold).percentMul(eModeCategory.liquidationBonus)
                <= PercentageMath.PERCENTAGE_FACTOR
        );

        _setEModeCategoryAsset(eModeCategory, dai, eModeCategoryId);

        indexes.supply.poolIndex = bound(indexes.supply.poolIndex, 0, type(uint96).max);
        indexes.supply.p2pIndex = bound(indexes.supply.p2pIndex, indexes.supply.poolIndex, type(uint96).max);
        indexes.borrow.p2pIndex = bound(indexes.borrow.p2pIndex, 0, type(uint96).max);
        indexes.borrow.poolIndex = bound(indexes.borrow.poolIndex, indexes.borrow.p2pIndex, type(uint96).max);
        /// Keep the condition because the test reverts if _E_MODE_CATEGORY_ID == 0
        if (_E_MODE_CATEGORY_ID != 0) {
            vm.assume(_E_MODE_CATEGORY_ID != eModeCategoryId);
            vm.expectRevert(abi.encodeWithSelector(Errors.InconsistentEMode.selector));
        }
        this.authorizeBorrow(dai, 0, indexes);
    }

    function authorizeBorrow(address underlying, uint256 amount, Types.Indexes256 memory indexes) public view {
        _authorizeBorrow(underlying, amount, indexes);
    }
}