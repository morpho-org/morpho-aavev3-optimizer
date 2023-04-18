// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@forge-std/Script.sol";

import {Types} from "src/libraries/Types.sol";

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPositionsManager} from "src/interfaces/IPositionsManager.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave-v3-core/interfaces/IPoolDataProvider.sol";
import {IAToken} from "@aave-v3-core/interfaces/IAToken.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Morpho} from "src/Morpho.sol";
import {PositionsManager} from "src/PositionsManager.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Config, ConfigLib} from "../helpers/ConfigLib.sol";

contract EthEModeDeploy is Script {
    using ConfigLib for Config;
    using SafeTransferLib for ERC20;

    uint8 internal constant E_MODE_CATEGORY_ID = 1; // ETH e-mode.
    uint128 internal constant MAX_ITERATIONS = 4;

    address[] internal assetsToList;

    address internal wEth;
    address internal wstEth;
    address internal rEth;
    address internal cbEth;
    address internal dai;
    address internal usdc;
    address internal wBtc;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;
    IPool internal pool;
    IPoolAddressesProvider internal addressesProvider;
    IPoolDataProvider internal poolDataProvider;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    Config internal config;

    function run() external {
        _initConfig();
        _loadConfig();

        vm.startBroadcast();

        _deploy();
        _createMarkets();
        _sendATokens();
        _setAssetsAsCollateral();
        _disableSupplyOnlyAndBorrow();

        // Pause Rewards as there is no rewards on Aave V3 Mainnet.
        morpho.setIsClaimRewardsPaused(true);

        vm.stopBroadcast();
    }

    function _initConfig() internal returns (Config storage) {
        if (bytes(config.json).length == 0) {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/config/ethereum-mainnet.json");

            config.json = vm.readFile(path);
        }

        return config;
    }

    function _loadConfig() internal {
        addressesProvider = IPoolAddressesProvider(config.getAddressesProvider());
        pool = IPool(addressesProvider.getPool());
        poolDataProvider = IPoolDataProvider(addressesProvider.getPoolDataProvider());

        wEth = config.getAddress("WETH");
        wstEth = config.getAddress("wstETH");
        rEth = config.getAddress("rETH");
        cbEth = config.getAddress("cbETH");
        dai = config.getAddress("DAI");
        usdc = config.getAddress("USDC");
        wBtc = config.getAddress("WBTC");

        assetsToList = [wEth, wstEth, rEth, cbEth, dai, usdc, wBtc];
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
        for (uint256 i; i < assetsToList.length; ++i) {
            // Create market.
            morpho.createMarket(assetsToList[i], 0, 0);

            // Send dust of listed assets to Morpho contract.
            address underlying = assetsToList[i];
            ERC20(underlying).safeTransfer(address(morpho), ERC20(underlying).balanceOf(msg.sender) / 2);
        }
    }

    function _sendATokens() internal {
        IPoolDataProvider.TokenData[] memory aTokens = poolDataProvider.getAllReservesTokens();

        // Send aTokens to Morpho contract.
        for (uint256 i; i < aTokens.length; ++i) {
            address aToken = aTokens[i].tokenAddress;
            ERC20(aToken).safeTransfer(address(morpho), ERC20(aToken).balanceOf(msg.sender) / 2);
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
        morpho.setIsSupplyPaused(cbEth, true);
        morpho.setIsSupplyPaused(rEth, true);
        morpho.setIsSupplyPaused(dai, true);
        morpho.setIsSupplyPaused(usdc, true);
        morpho.setIsSupplyPaused(wBtc, true);

        morpho.setIsBorrowPaused(wstEth, true);
        morpho.setIsBorrowPaused(cbEth, true);
        morpho.setIsBorrowPaused(rEth, true);
        morpho.setIsBorrowPaused(dai, true);
        morpho.setIsBorrowPaused(usdc, true);
        morpho.setIsBorrowPaused(wBtc, true);
    }
}
