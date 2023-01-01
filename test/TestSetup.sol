// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {console2} from "@forge-std/console2.sol";
import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";
import "@forge-std/Test.sol";

contract TestSetup is Test {
    // Common test variables between all networks
    IPoolAddressesProvider public addressesProvider;
    address public dai;
    address public usdc;
    address public usdt;
    address public wbtc;

    // The full list of markets to be tested when fuzzing or looping through all markets
    address[] public markets;

    uint256 public forkId;

    function setUp() public {
        configSetUp();
    }

    function configSetUp() public {
        string memory config = TestHelpers.getJsonConfig();
        string memory network = vm.envString("NETWORK");

        forkId = TestHelpers.setForkFromJson(config, network);

        addressesProvider =
            IPoolAddressesProvider(TestHelpers.getAddressFromJson(config, network, "LendingPoolAddressesProvider"));
        dai = TestHelpers.getAddressFromJson(config, network, "DAI");
        usdc = TestHelpers.getAddressFromJson(config, network, "USDC");
        usdt = TestHelpers.getAddressFromJson(config, network, "USDT");
        wbtc = TestHelpers.getAddressFromJson(config, network, "WBTC");

        markets = TestHelpers.getTestMarkets(config, network);
    }

    function testTest() public view {
        console2.log("test");
        for (uint256 i; i < markets.length; i++) {
            console2.log(markets[i]);
        }
    }
}
