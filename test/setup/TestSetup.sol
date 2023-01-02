// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {TestHelpers} from "../helpers/TestHelpers.sol";
import {User} from "../helpers/User.sol";
import {console2} from "@forge-std/console2.sol";
import {IPool, IPoolAddressesProvider} from "../../src/interfaces/aave/IPool.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {EntryPositionsManager} from "../../src/EntryPositionsManager.sol";
import {ExitPositionsManager} from "../../src/ExitPositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import {Types} from "../../src/libraries/Types.sol";

import {Test} from "@forge-std/Test.sol";

contract TestSetup is Test {
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

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

    User[] public users;

    User public supplier1;
    User public supplier2;
    User public supplier3;

    User public borrower1;
    User public borrower2;
    User public borrower3;

    function setUp() public virtual {
        configSetUp();
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
