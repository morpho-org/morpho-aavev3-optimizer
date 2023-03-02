// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IAToken} from "src/interfaces/aave/IAToken.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IACLManager} from "@aave-v3-core/interfaces/IACLManager.sol";
import {IPoolConfigurator} from "@aave-v3-core/interfaces/IPoolConfigurator.sol";
import {IPoolDataProvider} from "@aave-v3-core/interfaces/IPoolDataProvider.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IStableDebtToken} from "@aave-v3-core/interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "@aave-v3-core/interfaces/IVariableDebtToken.sol";

import {ReserveDataLib} from "src/libraries/ReserveDataLib.sol";
import {ReserveDataTestLib} from "test/helpers/ReserveDataTestLib.sol";
import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {MathUtils} from "@aave-v3-core/protocol/libraries/math/MathUtils.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {Errors as AaveErrors} from "@aave-v3-core/protocol/libraries/helpers/Errors.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {RewardsControllerMock} from "test/mocks/RewardsControllerMock.sol";
import {PriceOracleSentinelMock} from "test/mocks/PriceOracleSentinelMock.sol";
import {AaveOracleMock} from "test/mocks/AaveOracleMock.sol";
import {PoolAdminMock} from "test/mocks/PoolAdminMock.sol";
import "./BaseTest.sol";

contract ForkTest is BaseTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using TestConfigLib for TestConfig;
    using ReserveDataLib for DataTypes.ReserveData;
    using ReserveDataTestLib for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /* STRUCTS */

    struct StableDebtSupplyData {
        uint256 currPrincipalStableDebt;
        uint256 currTotalStableDebt;
        uint256 currAvgStableBorrowRate;
        uint40 stableDebtLastUpdateTimestamp;
    }

    /* STORAGE */

    address internal constant POOL_ADMIN = address(0xB055);

    string internal network;
    uint256 internal forkId;
    TestConfig internal config;

    address internal dai;
    address internal usdc;
    address internal aave;
    address internal link;
    address internal wbtc;
    address internal weth;
    address internal wNative;
    address[] internal allUnderlyings;

    IPool internal pool;
    IACLManager internal aclManager;
    IPoolConfigurator internal poolConfigurator;
    IPoolDataProvider internal poolDataProvider;
    IPoolAddressesProvider internal addressesProvider;
    address internal morphoDao;

    address internal aclAdmin;
    AaveOracleMock internal oracle;
    PoolAdminMock internal poolAdmin;
    PriceOracleSentinelMock internal oracleSentinel;
    RewardsControllerMock internal rewardsController;

    uint256 internal snapshotId = type(uint256).max;

    constructor() {
        _initConfig();
        _loadConfig();

        _mockPoolAdmin();
        _mockOracle();
        _mockOracleSentinel();
        _mockRewardsController();

        deal(address(this), type(uint128).max);
        _setBalances(address(this), type(uint96).max);
    }

    function setUp() public virtual {
        _label();
    }

    function _network() internal view returns (string memory) {
        try vm.envString("NETWORK") returns (string memory configNetwork) {
            return configNetwork;
        } catch {
            return "ethereum-mainnet";
        }
    }

    function _initConfig() internal returns (TestConfig storage) {
        if (bytes(config.json).length == 0) {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/config/", _network(), ".json");

            config.json = vm.readFile(path);
        }

        return config;
    }

    function _loadConfig() internal {
        string memory rpcAlias = config.getRpcAlias();
        Chain memory chain = getChain(rpcAlias);

        forkId = vm.createSelectFork(chain.rpcUrl, config.getForkBlockNumber());
        vm.chainId(chain.chainId);

        addressesProvider = IPoolAddressesProvider(config.getAddressesProvider());
        pool = IPool(addressesProvider.getPool());
        morphoDao = config.getMorphoDao();

        aclAdmin = addressesProvider.getACLAdmin();
        aclManager = IACLManager(addressesProvider.getACLManager());
        poolConfigurator = IPoolConfigurator(addressesProvider.getPoolConfigurator());
        poolDataProvider = IPoolDataProvider(addressesProvider.getPoolDataProvider());

        dai = config.getAddress("DAI");
        usdc = config.getAddress("USDC");
        aave = config.getAddress("AAVE");
        link = config.getAddress("LINK");
        wbtc = config.getAddress("WBTC");
        weth = config.getAddress("WETH");
        wNative = config.getWrappedNative();

        allUnderlyings = pool.getReservesList();
    }

    function _label() internal virtual {
        vm.label(address(pool), "Pool");
        vm.label(address(oracle), "PriceOracle");
        vm.label(address(addressesProvider), "AddressesProvider");

        vm.label(aclAdmin, "ACLAdmin");
        vm.label(address(aclManager), "ACLManager");
        vm.label(address(poolConfigurator), "PoolConfigurator");
        vm.label(address(poolDataProvider), "PoolDataProvider");

        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            string memory symbol = ERC20(underlying).symbol();

            vm.label(underlying, symbol);
        }
    }

    function _mockPoolAdmin() internal {
        poolAdmin = new PoolAdminMock(poolConfigurator);

        vm.startPrank(aclAdmin);
        aclManager.addPoolAdmin(address(poolAdmin));
        aclManager.addRiskAdmin(address(poolAdmin));
        aclManager.addEmergencyAdmin(address(poolAdmin));
        vm.stopPrank();
    }

    function _mockOracle() internal {
        oracle = new AaveOracleMock(IAaveOracle(addressesProvider.getPriceOracle()), allUnderlyings);

        vm.prank(aclAdmin);
        addressesProvider.setPriceOracle(address(oracle));
    }

    function _mockOracleSentinel() internal {
        oracleSentinel = new PriceOracleSentinelMock(address(addressesProvider));

        vm.prank(aclAdmin);
        addressesProvider.setPriceOracleSentinel(address(oracleSentinel));
    }

    function _mockRewardsController() internal {
        rewardsController = new RewardsControllerMock();
    }

    function _setBalances(address user, uint256 balance) internal {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];

            deal(underlying, user, balance / (10 ** (18 - ERC20(underlying).decimals())));
        }
    }

    /// @dev Avoids to revert because of AAVE token snapshots: https://github.com/aave/aave-token-v2/blob/master/contracts/token/base/GovernancePowerDelegationERC20.sol#L174

    function _deal(address underlying, address user, uint256 amount) internal {
        if (amount == 0) return;

        if (underlying == weth) deal(weth, weth.balance + amount); // Refill wrapped Ether.

        if (underlying == aave) {
            uint256 balance = ERC20(underlying).balanceOf(user);

            if (amount > balance) ERC20(underlying).safeTransfer(user, amount - balance);
            if (amount < balance) {
                vm.prank(user);
                ERC20(underlying).safeTransfer(address(this), balance - amount);
            }

            return;
        }

        deal(underlying, user, amount);
    }

    /// @dev Reverts the fork to its initial fork state.
    function _revert() internal {
        if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
    }

    /// @dev Returns the total supply used towards the supply cap.
    function _totalSupplyToCap(address underlying) internal view returns (uint256) {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(underlying);
        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlying);

        return reserve.totalSupplyToCap(poolSupplyIndex, poolBorrowIndex);
    }

    /// @dev Returns the total supply used towards the supply cap.
    function _setSupplyGap(address underlying, uint256 supplyGap) internal returns (uint256) {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(underlying);
        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlying);

        poolAdmin.setSupplyCap(
            underlying,
            (reserve.totalSupplyToCap(poolSupplyIndex, poolBorrowIndex) + supplyGap)
                / (10 ** reserve.configuration.getDecimals())
        );

        return reserve.supplyGap(poolSupplyIndex, poolBorrowIndex);
    }

    /// @dev Sets the borrow gap of AaveV3 to the given input.
    /// @return The new borrow gap after rounding since supply caps on AAVE are only granular up to the token's decimals.
    function _setBorrowGap(address underlying, uint256 borrowGap) internal returns (uint256) {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);

        poolAdmin.setBorrowCap(
            underlying, (reserve.totalBorrow() + borrowGap) / (10 ** reserve.configuration.getDecimals())
        );

        return reserve.borrowGap();
    }

    // @dev  Computes the valid lower bound for ltv and lt for a given CategoryEModeId, conditions required by Aave's code.
    // https://github.com/aave/aave-v3-core/blob/94e571f3a7465201881a59555314cd550ccfda57/contracts/protocol/pool/PoolConfigurator.sol#L369-L376
    function _getLtvLt(address underlying, uint8 eModeCategoryId)
        internal
        view
        returns (uint256 ltvBound, uint256 ltBound, uint256 ltvConfig, uint256 ltConfig)
    {
        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; ++i) {
            DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(reserves[i]);
            if (eModeCategoryId == currentConfig.getEModeCategory() || underlying == reserves[i]) {
                ltvBound = uint16(Math.max(ltvBound, currentConfig.getLtv()));

                ltBound = uint16(Math.max(ltBound, currentConfig.getLiquidationThreshold()));

                if (underlying == reserves[i]) {
                    ltvConfig = uint16(currentConfig.getLtv());
                    ltConfig = uint16(currentConfig.getLiquidationThreshold());
                }
            }
        }
    }

    function _setEModeCategoryAsset(
        DataTypes.EModeCategory memory eModeCategory,
        address underlying,
        uint8 eModeCategoryId
    ) internal {
        poolAdmin.setEModeCategory(
            eModeCategoryId,
            eModeCategory.ltv,
            eModeCategory.liquidationThreshold,
            eModeCategory.liquidationBonus,
            address(1),
            ""
        );
        poolAdmin.setAssetEModeCategory(underlying, eModeCategoryId);
    }
}
