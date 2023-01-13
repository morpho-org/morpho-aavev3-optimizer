// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IPositionsManager} from "../../src/interfaces/IPositionsManager.sol";
import {IMorpho} from "../../src/interfaces/IMorpho.sol";

import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TestUser} from "../helpers/TestUser.sol";

import {PositionsManager} from "../../src/PositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import "./ForkTest.sol";

contract IntegrationTest is ForkTest {
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant INITIAL_BALANCE = 10_000_000_000 ether;
    uint256 internal constant MIN_USD_AMOUNT = 0.001e8; // AaveV3 base currency is USD, 8 decimals on all L2s.
    uint256 internal constant MAX_USD_AMOUNT = 10_000_000_000e8; // AaveV3 base currency is USD, 8 decimals on all L2s.

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    TestUser internal user1;
    TestUser internal user2;
    TestUser internal user3;

    struct TestMarket {
        address aToken;
        address debtToken;
        address underlying;
        string symbol;
        uint256 decimals;
        //
        uint256 ltv;
        uint256 lt;
        uint256 liquidationBonus;
        uint256 supplyCap;
        //
        uint16 reserveFactor;
        uint16 p2pIndexCursor;
        //
        uint256 price;
        uint256 liquidity;
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

        user1 = _initUser();
        user2 = _initUser();
        user3 = _initUser();
    }

    function _label() internal override {
        super._label();

        vm.label(address(user1), "User1");
        vm.label(address(user2), "User2");
        vm.label(address(user3), "User3");
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

    function _initUser() internal returns (TestUser user) {
        user = new TestUser(address(morpho));

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
            supplyCap: 0,
            reserveFactor: reserveFactor,
            p2pIndexCursor: p2pIndexCursor,
            // Price is constant, equal to price at fork block number.
            price: oracle.getAssetPrice(underlying),
            liquidity: IAToken(reserve.aTokenAddress).totalSupply()
        });

        (market.ltv, market.lt, market.liquidationBonus, market.decimals,,) = reserve.configuration.getParams();
        market.supplyCap = reserve.configuration.getSupplyCap() * 10 ** market.decimals;

        markets.push(market);

        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function _boundSupply(TestMarket memory market, uint256 amount) internal view returns (uint256) {
        return bound(
            amount,
            (MIN_USD_AMOUNT * 10 ** market.decimals) / market.price,
            // TODO: may need to cap to type(uint96).max
            Math.min((MAX_USD_AMOUNT * 10 ** market.decimals) / market.price, market.supplyCap - market.liquidity - 1)
        );
    }

    function _boundBorrow(TestMarket memory market, uint256 amount) internal view returns (uint256) {
        return bound(
            amount,
            (MIN_USD_AMOUNT * 10 ** market.decimals) / market.price,
            // TODO: may need to cap to type(uint96).max / 2 to keep collateral < type(uint96).max
            Math.min(
                ERC20(market.underlying).balanceOf(market.aToken),
                (MAX_USD_AMOUNT * 10 ** market.decimals) / market.price
            )
        );
    }

    function _minimumCollateral(TestMarket memory collateralMarket, TestMarket memory borrowedMarket, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return (
            (amount * borrowedMarket.price * 10 ** collateralMarket.decimals).percentDiv(collateralMarket.ltv)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        );
    }
}
