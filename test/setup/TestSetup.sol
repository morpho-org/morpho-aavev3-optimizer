// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {TestConfig} from "../helpers/TestConfig.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {User} from "../helpers/User.sol";
import {console2} from "@forge-std/console2.sol";
import {IPool, IPoolAddressesProvider} from "../../src/interfaces/aave/IPool.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {PositionsManager} from "../../src/PositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import {Types} from "../../src/libraries/Types.sol";

import {Test} from "@forge-std/Test.sol";

contract TestSetup is Test {
    using TestConfig for TestConfig.Config;

    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    string internal network = vm.envString("NETWORK");
    uint256 internal forkId;
    TestConfig.Config internal config;

    // Common test variables between all networks
    IPoolAddressesProvider internal addressesProvider;
    IPool internal pool;
    address internal dai;
    address internal usdc;
    address internal usdt;
    address internal wbtc;
    address internal wNative;

    PositionsManager internal positionsManager;
    Morpho internal morphoImplementation;
    TransparentUpgradeableProxy internal morphoProxy;
    ProxyAdmin internal proxyAdmin;
    Morpho internal morpho;

    // The full list of markets to be tested when fuzzing or looping through all markets
    address[] internal markets;

    User[] internal users;

    User internal supplier1;
    User internal supplier2;
    User internal supplier3;

    User internal borrower1;
    User internal borrower2;
    User internal borrower3;

    constructor() {
        _loadConfig();
    }

    function _loadConfig() internal {
        config.load(network);

        forkId = config.createFork();

        addressesProvider = IPoolAddressesProvider(config.getAddress("addressesProvider"));
        pool = IPool(addressesProvider.getPool());

        dai = config.getAddress("DAI");
        usdc = config.getAddress("USDC");
        usdt = config.getAddress("USDT");
        wbtc = config.getAddress("WBTC");
        wNative = config.getAddress("wrappedNative");

        markets = config.getTestMarkets();
    }

    function setUp() public virtual {
        deployAndSet();
        initUsers(10, INITIAL_BALANCE);
        fillBalance(address(this), type(uint256).max);
        supplier1 = users[0];
        supplier2 = users[1];
        supplier3 = users[2];

        borrower1 = users[3];
        borrower2 = users[4];
        borrower3 = users[5];
    }

    function deployAndSet() internal {
        positionsManager = new PositionsManager(address(addressesProvider));
        morphoImplementation = new Morpho(address(addressesProvider));

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImplementation)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(address(positionsManager), Types.MaxLoops({supply: 10, borrow: 10, repay: 10, withdraw: 10}));

        createMarket(dai);
    }

    function createMarket(address underlying) internal {
        morpho.createMarket(underlying, 0, 3_333);
    }

    function initUsers(uint256 numUsers, uint256 initialBalance) internal {
        for (uint256 i = 0; i < numUsers; i++) {
            initUser(initialBalance);
        }
    }

    function initUser(uint256 balance) internal {
        User user = new User(morpho);

        vm.label(address(user), "User");
        fillBalance(address(user), balance);
        users.push(user);
    }

    function fillBalance(address user, uint256 balance) internal {
        deal(dai, address(user), balance);
        deal(usdc, address(user), balance);
        deal(usdt, address(user), balance);
        deal(wbtc, address(user), balance);
        deal(wNative, address(user), balance);
    }
}
