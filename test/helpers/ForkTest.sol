// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IPool, IPoolAddressesProvider} from "../../src/interfaces/aave/IPool.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";

import {Types} from "../../src/libraries/Types.sol";
import {Events} from "../../src/libraries/Events.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {DataTypes} from "../../src/libraries/aave/DataTypes.sol";
import {TestConfig, TestConfigLib} from "../helpers/TestConfigLib.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {console2} from "@forge-std/console2.sol";
import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";

contract ForkTest is Test {
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
    IPriceOracleGetter internal oracle;
    IPoolAddressesProvider internal addressesProvider;

    uint256 snapshotId = type(uint256).max;

    constructor() {
        _initConfig();
        _loadConfig();
        _label();

        _setBalances(address(this), type(uint256).max);
    }

    function setUp() public virtual {}

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
        oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

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

    /// @dev Rolls & warps `_blocks` blocks forward the blockchain.
    function _forward(uint256 _blocks) internal {
        vm.roll(block.number + _blocks);
        vm.warp(block.timestamp + _blocks * 12);
    }

    /// @dev Reverts the fork to its initial fork state.
    function _revert() internal {
        if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
    }
}
