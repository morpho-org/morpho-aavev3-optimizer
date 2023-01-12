// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IPositionsManager} from "../../src/interfaces/IPositionsManager.sol";
import {IMorpho} from "../../src/interfaces/IMorpho.sol";

import {ReserveConfiguration} from "../../src/libraries/aave/ReserveConfiguration.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TestUser} from "../helpers/TestUser.sol";

import {PositionsManager} from "../../src/PositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import "./ForkTest.sol";

contract IntegrationTest is ForkTest {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    TransparentUpgradeableProxy internal morphoProxy;
    IMorpho internal morphoImpl;

    TestUser internal user1;
    TestUser internal user2;
    TestUser internal user3;

    struct TestMarket {
        address aToken;
        address debtToken;
        address underlying;
        string symbol;
        uint256 decimals;
        uint256 ltv;
        uint256 lt;
        uint256 liquidationBonus;
        uint16 reserveFactor;
        uint16 p2pIndexCursor;
    }

    TestMarket[] public markets;

    function setUp() public virtual override {
        super.setUp();

        _deploy();

        _initMarket(dai, 0, 33_33);
        _initMarket(usdc, 0, 33_33);
        _initMarket(usdt, 0, 33_33);
        _initMarket(aave, 0, 33_33);
        _initMarket(link, 0, 33_33);
        _initMarket(wavax, 0, 33_33);
        _initMarket(wbtc, 0, 33_33);
        _initMarket(weth, 0, 33_33);

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

    function _initMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        string memory symbol = ERC20(underlying).symbol();
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);

        TestMarket memory market = TestMarket({
            aToken: reserve.aTokenAddress,
            debtToken: reserve.variableDebtTokenAddress,
            underlying: underlying,
            symbol: symbol,
            decimals: 0,
            ltv: 0,
            lt: 0,
            liquidationBonus: 0,
            reserveFactor: reserveFactor,
            p2pIndexCursor: p2pIndexCursor
        });

        (market.ltv, market.lt, market.liquidationBonus, market.decimals,,) = reserve.configuration.getParams();

        markets.push(market);

        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }
}
