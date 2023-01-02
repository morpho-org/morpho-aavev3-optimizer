// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {console2} from "@forge-std/console2.sol";
import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {EntryPositionsManager} from "../src/EntryPositionsManager.sol";
import {ExitPositionsManager} from "../src/ExitPositionsManager.sol";
import {Morpho} from "../src/Morpho.sol";

import {Types} from "../src/libraries/Types.sol";

import {Test} from "@forge-std/Test.sol";

contract TestSetup is Test {
    // Common test variables between all networks
    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    address public dai;
    address public usdc;
    address public usdt;
    address public wbtc;
    address public wNative;

    EntryPositionsManager public entryPositionsManager;
    ExitPositionsManager public exitPositionsManager;
    Morpho public morphoImplementation;
    TransparentUpgradeableProxy public morphoProxy;
    ProxyAdmin public proxyAdmin;
    Morpho public morpho;

    // The full list of markets to be tested when fuzzing or looping through all markets
    address[] public markets;

    uint256 public forkId;

    function setUp() public {
        configSetUp();
        deployAndSet();
    }

    function configSetUp() public {
        string memory network = vm.envString("NETWORK");
        string memory config = TestHelpers.getJsonConfig(network);

        forkId = TestHelpers.setForkFromJson(config);

        addressesProvider =
            IPoolAddressesProvider(TestHelpers.getAddressFromJson(config, "LendingPoolAddressesProvider"));
        pool = IPool(addressesProvider.getPool());
        dai = TestHelpers.getAddressFromJson(config, "DAI");
        usdc = TestHelpers.getAddressFromJson(config, "USDC");
        usdt = TestHelpers.getAddressFromJson(config, "USDT");
        wbtc = TestHelpers.getAddressFromJson(config, "WBTC");
        wNative = TestHelpers.getAddressFromJson(config, "wrappedNative");

        markets = TestHelpers.getTestMarkets(config);
    }

    function deployAndSet() public {
        entryPositionsManager = new EntryPositionsManager();
        exitPositionsManager = new ExitPositionsManager();
        morphoImplementation = new Morpho();

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImplementation)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(
            address(entryPositionsManager),
            address(exitPositionsManager),
            address(addressesProvider),
            Types.MaxLoops({supply: 10, borrow: 10, repay: 10, withdraw: 10}),
            20
        );

        createMarket(dai);
    }

    function createMarket(address underlying) public {
        morpho.createMarket(underlying, 0, 3_333);
    }

    function testTest() public view {
        console2.log("test");
        for (uint256 i; i < markets.length; i++) {
            console2.log(markets[i]);
        }
    }
}
