// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IPositionsManager} from "../../src/interfaces/IPositionsManager.sol";
import {IMorpho} from "../../src/interfaces/IMorpho.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TestUser} from "../helpers/TestUser.sol";

import {PositionsManager} from "../../src/PositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import "./ForkTest.sol";

contract IntegrationTest is ForkTest {
    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    TransparentUpgradeableProxy internal morphoProxy;
    IMorpho internal morphoImpl;

    TestUser internal user1;
    TestUser internal user2;
    TestUser internal user3;

    function setUp() public virtual override {
        super.setUp();

        _deploy();

        user1 = _initUser(string.concat("User1"));
        user2 = _initUser(string.concat("User2"));
        user3 = _initUser(string.concat("User3"));
    }

    function _deploy() internal {
        positionsManager = new PositionsManager(address(addressesProvider));
        morphoImpl = new Morpho(address(addressesProvider));

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(
            address(positionsManager), Types.MaxLoops({supply: 10, borrow: 10, repay: 10, withdraw: 10}), 20
        );

        morpho.createMarket(dai, 0, 33_33);
    }

    function _initUser(string memory name) internal returns (TestUser user) {
        user = new TestUser(address(morpho));

        vm.label(address(user), name);
        _setBalances(address(user), INITIAL_BALANCE);
    }

    function _createForkFromEnv() internal {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }
}
