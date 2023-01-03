// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {EntryPositionsManager} from "../src/EntryPositionsManager.sol";
import {ExitPositionsManager} from "../src/ExitPositionsManager.sol";
import {Morpho} from "../src/Morpho.sol";

import {Types} from "../src/libraries/Types.sol";

import {Test as ForgeTest} from "@forge-std/Test.sol";
import {console2} from "@forge-std/console2.sol";

contract Test is ForgeTest {
    IPool pool;
    IPoolAddressesProvider addressesProvider;
    ProxyAdmin proxyAdmin;

    address dai;
    address usdc;
    address usdt;
    address wbtc;
    address wNative;

    Morpho morphoImpl;

    Morpho morpho;
    EntryPositionsManager entryPositionsManager;
    ExitPositionsManager exitPositionsManager;

    TransparentUpgradeableProxy morphoProxy;

    address[] testMarkets;

    struct TestMarket {
        address poolToken;
        address debtToken;
        address underlying;
        string symbol;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        Types.Market config;
        //
        bool isActive;
        bool isFrozen;
        //
        Types.PauseStatuses status;
    }

    TestMarket[] public markets;
    TestMarket[] public activeMarkets;
    TestMarket[] public unpausedMarkets;
    TestMarket[] public collateralMarkets;
    TestMarket[] public borrowableMarkets;
    TestMarket[] public borrowableCollateralMarkets;

    uint256 forkId;
    uint256 snapshotId = type(uint256).max;

    function setUp() public virtual {
        _configSetUp();
        _deployAndSet();
    }

    function _configSetUp() public {
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

        testMarkets = TestHelpers.getTestMarkets(config);
    }

    function _deployAndSet() public {
        proxyAdmin = new ProxyAdmin();

        morphoImpl = new Morpho();
        entryPositionsManager = new EntryPositionsManager();
        exitPositionsManager = new ExitPositionsManager();

        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(
            address(entryPositionsManager),
            address(exitPositionsManager),
            address(addressesProvider),
            Types.MaxLoops({supply: 10, borrow: 10, repay: 10, withdraw: 10}),
            20
        );

        for (uint256 i; i < testMarkets.length; ++i) {
            _createMarket(testMarkets[i]);
        }
    }

    function _createMarket(address underlying) public {
        morpho.createMarket(underlying, 0, 3_333);
    }
}
