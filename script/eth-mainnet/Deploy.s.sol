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
    uint256 internal constant LT_LOWER_BOUND = 10_00;

    address internal dai;
    address internal usdc;
    address internal wbtc;

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

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _deploy();
        morpho.createMarket(dai, 3_333, 3_333);
        morpho.createMarket(usdc, 3_333, 3_333);
        morpho.createMarket(wbtc, 3_333, 3_333);
        vm.stopBroadcast();
    }

    function _initConfig() internal returns (TestConfig storage) {
        if (bytes(config.json).length == 0) {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/config/ethereum-mainnet.json");

            config.json = vm.readFile(path);
        }

        return config;
    }

    function _loadConfig() internal {
        addressesProvider = IPoolAddressesProvider(config.getAddressesProvider());

        dai = config.getAddress("DAI");
        usdc = config.getAddress("USDC");
        wbtc = config.getAddress("WBTC");
    }

    function _deploy() internal {
        positionsManager = new PositionsManager(address(addressesProvider), E_MODE_CATEGORY_ID);
        morphoImpl = new Morpho(address(addressesProvider), E_MODE_CATEGORY_ID);

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(
            payable(address(morphoImpl)), 
            address(proxyAdmin), 
            abi.encodeWithSelector(
                morphoImpl.initialize.selector, 
                address(positionsManager), 
                Types.Iterations({repay: 10, withdraw: 10})));
        morpho = Morpho(payable(address(morphoProxy)));
    }
}
