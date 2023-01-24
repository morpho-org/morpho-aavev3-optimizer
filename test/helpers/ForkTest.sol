// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IAToken} from "src/interfaces/aave/IAToken.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IVariableDebtToken} from "@aave-v3-core/interfaces/IVariableDebtToken.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";

import {Types} from "src/libraries/Types.sol";
import {Events} from "src/libraries/Events.sol";
import {Errors} from "src/libraries/Errors.sol";
import {TestConfig, TestConfigLib} from "../helpers/TestConfigLib.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";

import {AaveOracleMock} from "../mocks/AaveOracleMock.sol";

import "./BaseTest.sol";

contract ForkTest is BaseTest {
    using TestConfigLib for TestConfig;

    string internal network;
    uint256 internal forkId;
    TestConfig internal config;

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
    address[] internal testMarkets;

    IPool internal pool;
    AaveOracleMock internal oracle;
    IPoolAddressesProvider internal addressesProvider;

    uint256 snapshotId = type(uint256).max;

    constructor() {
        _initConfig();
        _loadConfig();

        _mockOracle();

        _setBalances(address(this), type(uint256).max);
    }

    function setUp() public virtual {
        _label();
    }

    function _network() internal view returns (string memory) {
        try vm.envString("NETWORK") returns (string memory configNetwork) {
            return configNetwork;
        } catch {
            return "avalanche-mainnet";
        }
    }

    function _initConfig() internal returns (TestConfig storage) {
        network = _network();

        return config.load(network);
    }

    function _loadConfig() internal {
        forkId = config.createFork();

        addressesProvider = IPoolAddressesProvider(config.getAddress("addressesProvider"));
        pool = IPool(addressesProvider.getPool());

        dai = config.getAddress("DAI");
        frax = config.getAddress("FRAX");
        mai = config.getAddress("MAI");
        usdc = config.getAddress("USDC");
        usdt = config.getAddress("USDT");
        aave = config.getAddress("AAVE");
        btcb = config.getAddress("BTCb");
        link = config.getAddress("LINK");
        sAvax = config.getAddress("sAVAX");
        wavax = config.getAddress("WAVAX");
        wbtc = config.getAddress("WBTC");
        weth = config.getAddress("WETH");
        wNative = config.getAddress("wrappedNative");

        testMarkets = config.getTestMarkets();
    }

    function _label() internal virtual {
        vm.label(address(pool), "Pool");
        vm.label(address(oracle), "PriceOracle");
        vm.label(address(addressesProvider), "AddressesProvider");

        vm.label(dai, "DAI");
        vm.label(frax, "FRAX");
        vm.label(mai, "MAI");
        vm.label(usdc, "USDC");
        vm.label(usdt, "USDT");
        vm.label(aave, "AAVE");
        vm.label(btcb, "BTCB");
        vm.label(link, "LINK");
        vm.label(sAvax, "sAVAX");
        vm.label(wavax, "WAVAX");
        vm.label(wbtc, "WBTC");
        vm.label(weth, "WETH");
        vm.label(wNative, "wNative");
    }

    function _mockOracle() internal {
        oracle = new AaveOracleMock(IAaveOracle(addressesProvider.getPriceOracle()), pool.getReservesList());

        vm.store(
            address(addressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(oracle))))
        );
    }

    function _setBalances(address user, uint256 balance) internal {
        deal(dai, user, balance);
        deal(frax, user, balance);
        deal(mai, user, balance);
        deal(usdc, user, balance / 1e6);
        deal(usdt, user, balance / 1e6);
        deal(aave, user, balance);
        deal(btcb, user, balance / 1e8);
        deal(link, user, balance);
        deal(sAvax, user, balance);
        deal(wavax, user, balance);
        deal(wbtc, user, balance / 1e8);
        deal(weth, user, balance);
        deal(wNative, user, balance);
    }

    /// @dev Reverts the fork to its initial fork state.
    function _revert() internal {
        if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
    }
}
