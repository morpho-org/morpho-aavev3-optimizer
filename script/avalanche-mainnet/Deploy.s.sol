// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {Types} from "src/libraries/Types.sol";

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPositionsManager} from "src/interfaces/IPositionsManager.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Morpho} from "src/Morpho.sol";
import {PositionsManager} from "src/PositionsManager.sol";

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";

contract Deploy is Script {
    using TestConfigLib for TestConfig;

    uint8 internal constant E_MODE_CATEGORY_ID = 0;

    address internal dai;
    address internal frax;
    address internal mai;
    address internal usdc;
    address internal usdt;
    address internal aave;
    address internal btcb;
    address internal link;
    address internal sAvax;
    address internal wavax;
    address internal wbtc;
    address internal weth;
    address internal wNative;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;
    IPoolAddressesProvider internal addressesProvider;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    TestConfig internal config;

    function run() external {
        _initConfig();
        _loadConfig();

        vm.startBroadcast();
        _deploy();
        morpho.createMarket(dai, 3_333, 3_333);
        morpho.createMarket(usdc, 3_333, 3_333);
        morpho.createMarket(btcb, 3_333, 3_333);
        vm.stopBroadcast();
    }

    function _initConfig() internal returns (TestConfig storage) {
        return config.load("avalanche-mainnet");
    }

    function _loadConfig() internal {
        addressesProvider = IPoolAddressesProvider(config.getAddressesProvider());

        dai = config.getAddress("$.DAI");
        frax = config.getAddress("$.FRAX");
        mai = config.getAddress("$.MAI");
        usdc = config.getAddress("$.USDC");
        usdt = config.getAddress("$.USDT");
        aave = config.getAddress("$.AAVE");
        btcb = config.getAddress("$.BTCb");
        link = config.getAddress("$.LINK");
        sAvax = config.getAddress("$.sAVAX");
        wavax = config.getAddress("$.WAVAX");
        wbtc = config.getAddress("$.WBTC");
        weth = config.getAddress("$.WETH");
        wNative = config.getAddress("$.wrappedNative");
    }

    function _deploy() internal {
        positionsManager = new PositionsManager(address(addressesProvider), E_MODE_CATEGORY_ID);
        morphoImpl = new Morpho(address(addressesProvider), E_MODE_CATEGORY_ID);

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(address(positionsManager), Types.MaxIterations({repay: 10, withdraw: 10}));
    }
}
