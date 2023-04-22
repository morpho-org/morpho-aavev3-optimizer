// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPositionsManager} from "src/interfaces/IPositionsManager.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave-v3-core/interfaces/IPoolDataProvider.sol";
import {IAToken} from "@aave-v3-core/interfaces/IAToken.sol";

import {Types} from "src/libraries/Types.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Morpho} from "src/Morpho.sol";
import {PositionsManager} from "src/PositionsManager.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Configured, ConfigLib, Config} from "config/Configured.sol";
import "@forge-std/Script.sol";
import "@forge-std/Test.sol";

contract EthEModeDeploy is Script, Test, Configured {
    using ConfigLib for Config;
    using SafeTransferLib for ERC20;

    uint8 internal constant E_MODE_CATEGORY_ID = 1; // ETH e-mode.
    uint128 internal constant MAX_ITERATIONS = 4;
    uint256 internal constant DUST = 1_000;

    address[] internal assetsToList;

    address internal wstEth;
    address internal rEth;
    address internal cbEth;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;
    IPool internal pool;
    IPoolAddressesProvider internal addressesProvider;
    IPoolDataProvider internal poolDataProvider;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    function run() external {
        _initConfig();
        _loadConfig();

        vm.startBroadcast(vm.envAddress("DEPLOYER"));

        _deploy();
        _createMarkets();
        _sendUnderlyings();
        _sendATokens();
        _setAssetsAsCollateral();
        _disableSupplyOnlyAndBorrow();

        // Pause Rewards as there is no rewards on Aave V3 Mainnet.
        morpho.setIsClaimRewardsPaused(true);

        vm.stopBroadcast();

        assertEq(pool.getUserEMode(address(morpho)), E_MODE_CATEGORY_ID);

        assertFalse(morpho.market(weth).pauseStatuses.isSupplyPaused);
        assertFalse(morpho.market(weth).pauseStatuses.isBorrowPaused);
        assertTrue(morpho.market(weth).isCollateral);

        assertTrue(morpho.market(wstEth).pauseStatuses.isSupplyPaused);
        assertTrue(morpho.market(wstEth).pauseStatuses.isBorrowPaused);
        assertTrue(morpho.market(wstEth).isCollateral);

        assertTrue(morpho.market(dai).pauseStatuses.isSupplyPaused);
        assertTrue(morpho.market(dai).pauseStatuses.isBorrowPaused);
        assertTrue(morpho.market(dai).isCollateral);

        assertTrue(morpho.market(usdc).pauseStatuses.isSupplyPaused);
        assertTrue(morpho.market(usdc).pauseStatuses.isBorrowPaused);
        assertTrue(morpho.market(usdc).isCollateral);

        assertTrue(morpho.market(wbtc).pauseStatuses.isSupplyPaused);
        assertTrue(morpho.market(wbtc).pauseStatuses.isBorrowPaused);
        assertTrue(morpho.market(wbtc).isCollateral);
    }

    function _network() internal pure virtual override returns (string memory) {
        return "ethereum-mainnet";
    }

    function _loadConfig() internal virtual override {
        super._loadConfig();

        addressesProvider = IPoolAddressesProvider(config.getAddressesProvider());
        pool = IPool(addressesProvider.getPool());
        poolDataProvider = IPoolDataProvider(addressesProvider.getPoolDataProvider());

        wstEth = config.getAddress("wstETH");

        assetsToList = [weth, wstEth, dai, usdc, wbtc];
    }

    function _deploy() internal {
        positionsManager = new PositionsManager();
        morphoImpl = new Morpho();

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(
            payable(address(morphoImpl)),
            address(proxyAdmin),
            abi.encodeWithSelector(
                morphoImpl.initialize.selector,
                address(addressesProvider),
                E_MODE_CATEGORY_ID,
                address(positionsManager),
                Types.Iterations({repay: MAX_ITERATIONS, withdraw: MAX_ITERATIONS})
            )
        );
        morpho = Morpho(payable(address(morphoProxy)));
    }

    function _createMarkets() internal {
        morpho.createMarket(weth, 0, 50_00);
        morpho.createMarket(wstEth, 0, 0);
        morpho.createMarket(dai, 0, 0);
        morpho.createMarket(usdc, 0, 0);
        morpho.createMarket(wbtc, 0, 0);
    }

    function _sendUnderlyings() internal {
        ERC20(weth).safeTransfer(address(morpho), DUST);
        ERC20(wstEth).safeTransfer(address(morpho), DUST);
        ERC20(dai).safeTransfer(address(morpho), DUST);
        ERC20(usdc).safeTransfer(address(morpho), DUST);
        ERC20(wbtc).safeTransfer(address(morpho), DUST);
    }

    function _sendATokens() internal {
        IPoolDataProvider.TokenData[] memory aTokens = poolDataProvider.getAllATokens();

        // Send aTokens to Morpho contract.
        for (uint256 i; i < aTokens.length; ++i) {
            address aToken = aTokens[i].tokenAddress;
            ERC20(aToken).safeTransfer(address(morpho), DUST);
            morpho.setAssetIsCollateralOnPool(IAToken(aToken).UNDERLYING_ASSET_ADDRESS(), false);
        }
    }

    function _setAssetsAsCollateral() internal {
        for (uint256 i; i < assetsToList.length; ++i) {
            address underlying = assetsToList[i];
            morpho.setAssetIsCollateralOnPool(underlying, true);
            morpho.setAssetIsCollateral(underlying, true);
        }
    }

    function _disableSupplyOnlyAndBorrow() internal {
        morpho.setIsSupplyPaused(wstEth, true);
        morpho.setIsSupplyPaused(dai, true);
        morpho.setIsSupplyPaused(usdc, true);
        morpho.setIsSupplyPaused(wbtc, true);

        morpho.setIsBorrowPaused(wstEth, true);
        morpho.setIsBorrowPaused(dai, true);
        morpho.setIsBorrowPaused(usdc, true);
        morpho.setIsBorrowPaused(wbtc, true);
    }
}
