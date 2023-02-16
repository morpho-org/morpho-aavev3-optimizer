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
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";
import {TestMarket, TestMarketLib} from "test/helpers/TestMarketLib.sol";
/// Assumption : Unit Test made for only one E-mode

contract TestInternalEMode is IntegrationTest, PositionsManagerInternal {
    using MarketLib for Types.Market;
    using PoolLib for IPool;
    using MarketBalanceLib for Types.MarketBalances;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using Math for uint256;
    using TestConfigLib for TestConfig;
    using SafeTransferLib for ERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    constructor() MorphoStorage(_initConfig().getAddressesProvider(), uint8(vm.envUint("E_MODE_CATEGORY_ID"))) {}

    function setUp() public virtual override {
        super.setUp();

        _defaultIterations = Types.Iterations(10, 10);

        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);
    }

    function testInitializeEMode() public {
        uint256 eModeCategoryId = vm.envUint("E_MODE_CATEGORY_ID");
        assertEq(_E_MODE_CATEGORY_ID, eModeCategoryId);
    }

    struct AssetInformation {
        uint256 underlyingPrice;
        uint256 underlyingPriceEMode;
        uint16 ltvEMode;
        uint16 ltEMode;
    }

    function testLtvLiquidationThresholdPriceSourceEMode(AssetInformation memory assetInfo) public {
        for (uint256 i; i < underlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            (uint16 ltvBound, uint16 ltBound, uint16 ltvConfig, uint16 ltConfig) = getLtvLt(underlying);

            assetInfo.ltEMode = uint16(bound(assetInfo.ltEMode, ltBound + 1, type(uint16).max));
            assetInfo.ltvEMode = uint16(bound(assetInfo.ltvEMode, ltvBound + 1, assetInfo.ltEMode));
            uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);
            assetInfo.underlyingPrice = bound(assetInfo.underlyingPrice, 0, type(uint96).max - 1);
            assetInfo.underlyingPriceEMode = bound(assetInfo.underlyingPriceEMode, 0, type(uint96).max);
            vm.assume(
                uint256(assetInfo.ltEMode).percentMul(uint256(liquidationBonus)) <= PercentageMath.PERCENTAGE_FACTOR
            );
            vm.assume(assetInfo.underlyingPrice != assetInfo.underlyingPriceEMode);

            DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
                ltv: assetInfo.ltvEMode,
                liquidationThreshold: assetInfo.ltEMode,
                liquidationBonus: liquidationBonus,
                priceSource: address(1),
                label: ""
            });
            if (_E_MODE_CATEGORY_ID != 0) {
                setEModeCategoryAsset(eModeCategory, underlying, _E_MODE_CATEGORY_ID);
            }

            oracle.setAssetPrice(address(1), assetInfo.underlyingPriceEMode);
            oracle.setAssetPrice(underlying, assetInfo.underlyingPrice);

            Types.LiquidityVars memory vars;
            vars.oracle = oracle;
            vars.user = address(this);
            vars.eModeCategory = eModeCategory;
            (uint256 assetPrice, uint256 ltv, uint256 lt,) = _assetLiquidityData(underlying, vars);

            assertEq(
                uint16(ltv),
                _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? assetInfo.ltvEMode : ltvConfig,
                "Loan to value E-mode"
            );
            assertEq(
                uint16(lt),
                _E_MODE_CATEGORY_ID != 0 && ltvConfig != 0 ? assetInfo.ltEMode : ltConfig,
                "Liquidation Threshold E-Mode"
            );
            assertEq(
                assetPrice,
                _E_MODE_CATEGORY_ID != 0 && assetInfo.underlyingPriceEMode != 0
                    ? assetInfo.underlyingPriceEMode
                    : assetInfo.underlyingPrice,
                "Underlying Price E-Mode"
            );
        }
    }

    function getLtvLt(address underlying)
        internal
        view
        returns (uint16 ltvBound, uint16 ltBound, uint16 ltvConfig, uint16 ltConfig)
    {
        address[] memory reserves = _POOL.getReservesList();
        for (uint256 j = 0; j < reserves.length; ++j) {
            DataTypes.ReserveConfigurationMap memory currentConfig = _POOL.getConfiguration(reserves[j]);
            if (_E_MODE_CATEGORY_ID == currentConfig.getEModeCategory() || underlying == reserves[j]) {
                ltvBound = uint16(Math.max(ltvConfig, (currentConfig.data & ~ReserveConfiguration.LTV_MASK)));
                ltBound = uint16(
                    Math.max(
                        ltConfig,
                        (currentConfig.data & ~ReserveConfiguration.LIQUIDATION_THRESHOLD_MASK)
                            >> ReserveConfiguration.LIQUIDATION_THRESHOLD_START_BIT_POSITION
                    )
                );
                if (underlying == reserves[j]) {
                    ltvConfig = uint16((currentConfig.data & ~ReserveConfiguration.LTV_MASK));
                    ltConfig = uint16(
                        (currentConfig.data & ~ReserveConfiguration.LIQUIDATION_THRESHOLD_MASK)
                            >> ReserveConfiguration.LIQUIDATION_THRESHOLD_START_BIT_POSITION
                    );
                }
            }
        }
    }

    function setEModeCategoryAsset(
        DataTypes.EModeCategory memory eModeCategory,
        address underlying,
        uint8 EModeCategoryId
    ) internal {
        vm.startPrank(address(poolAdmin));
        poolConfigurator.setEModeCategory(
            EModeCategoryId,
            eModeCategory.ltv,
            eModeCategory.liquidationThreshold,
            eModeCategory.liquidationBonus,
            address(1),
            ""
        );
        poolConfigurator.setAssetEModeCategory(underlying, EModeCategoryId);
        vm.stopPrank();
    }

    function testIsInEModeCategory(uint8 eModeCategoryId, uint16 lt, uint16 ltv, uint16 liquidationBonus) public {
        for (uint256 i; i < underlyings.length; ++i) {
            address underlying = underlyings[i];
            (uint16 ltvBound, uint16 ltBound,,) = getLtvLt(underlying);

            address priceSourceEMode = address(1);
            ltv = uint16(bound(ltv, ltvBound + 1, PercentageMath.PERCENTAGE_FACTOR));
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

            setEModeCategoryAsset(eModeCategory, underlying, EModeCategoryId);

            DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(underlying);
            bool expectedIsInEMode = _E_MODE_CATEGORY_ID == 0 && _E_MODE_CATEGORY_ID != 0;
            bool isInEMode = _isInEModeCategory(config);

            assertEq(isInEMode, expectedIsInEMode, "Wrong E-Mode");
        }
    }

    function testGetAssetPrice(
        address underlying,
        address priceSourceEMode,
        uint256 underlyingPriceEMode,
        uint256 underlyingPrice,
        bool isInEMode
    ) public {
        priceSourceEMode = address(uint160(bound(uint256(uint160(priceSourceEMode)), 0, type(uint160).max)));
        vm.assume(underlying != priceSourceEMode);

        underlyingPriceEMode = bound(underlyingPriceEMode, 0, type(uint256).max);
        underlyingPrice = bound(underlyingPrice, 0, type(uint256).max);

        oracle.setAssetPrice(underlying, underlyingPrice);
        oracle.setAssetPrice(priceSourceEMode, underlyingPriceEMode);

        uint256 expectedPrice = isInEMode && underlyingPriceEMode != 0 ? underlyingPriceEMode : underlyingPrice;
        uint256 realPrice = _getAssetPrice(underlying, oracle, isInEMode, priceSourceEMode);

        assertEq(expectedPrice, realPrice, "Wrong price");
    }

    function testAuthorizeBorrowEmode(
        uint8 eModeCategoryId,
        uint256 poolSupplyIndex,
        uint256 p2pSupplyIndex,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex
    ) public {
        address priceSourceEMode = address(1);

        uint16 ltv = uint16(PercentageMath.PERCENTAGE_FACTOR - 20);
        uint16 lt = uint16(PercentageMath.PERCENTAGE_FACTOR - 10);
        uint16 liquidationBonus = uint16(PercentageMath.PERCENTAGE_FACTOR + 1);

        eModeCategoryId = uint8(bound(uint256(eModeCategoryId), 1, type(uint8).max));

        DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
            ltv: ltv,
            liquidationThreshold: lt,
            liquidationBonus: liquidationBonus,
            priceSource: priceSourceEMode,
            label: ""
        });

        setEModeCategoryAsset(eModeCategory, dai, eModeCategoryId);

        Types.Indexes256 memory indexes;

        poolSupplyIndex = bound(poolSupplyIndex, 0, type(uint96).max);
        p2pSupplyIndex = bound(p2pSupplyIndex, poolSupplyIndex, type(uint96).max);
        p2pBorrowIndex = bound(p2pBorrowIndex, 0, type(uint96).max);
        poolBorrowIndex = bound(poolBorrowIndex, p2pBorrowIndex, type(uint96).max);

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
