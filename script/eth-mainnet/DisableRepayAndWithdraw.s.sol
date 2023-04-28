// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "src/interfaces/IMorpho.sol";

import {Configured, ConfigLib, Config} from "config/Configured.sol";
import "@forge-std/Script.sol";
import "@forge-std/Test.sol";

contract DisableRepayAndWithdraw is Script, Test, Configured {
    using ConfigLib for Config;

    IMorpho internal constant MORPHO = IMorpho(0x333F4448435Ba2D05e2B2CCd15dD50eA36839333);

    address internal wstEth;

    function run() external {
        _initConfig();
        _loadConfig();

        vm.startBroadcast(vm.envAddress("DEPLOYER"));

        _disableRepayAndWithdraw();

        vm.stopBroadcast();

        _checkAssertions();
    }

    function _network() internal pure virtual override returns (string memory) {
        return "ethereum-mainnet";
    }

    function _loadConfig() internal virtual override {
        super._loadConfig();

        wstEth = config.getAddress("wstETH");
    }

    function _disableRepayAndWithdraw() internal {
        MORPHO.setIsRepayPaused(wstEth, true);
        MORPHO.setIsRepayPaused(dai, true);
        MORPHO.setIsRepayPaused(usdc, true);
        MORPHO.setIsRepayPaused(wbtc, true);

        MORPHO.setIsWithdrawPaused(wstEth, true);
        MORPHO.setIsWithdrawPaused(dai, true);
        MORPHO.setIsWithdrawPaused(usdc, true);
        MORPHO.setIsWithdrawPaused(wbtc, true);
    }

    function _checkAssertions() internal {
        assertTrue(MORPHO.market(wstEth).pauseStatuses.isRepayPaused);
        assertTrue(MORPHO.market(wstEth).pauseStatuses.isWithdrawPaused);

        assertTrue(MORPHO.market(dai).pauseStatuses.isRepayPaused);
        assertTrue(MORPHO.market(dai).pauseStatuses.isWithdrawPaused);

        assertTrue(MORPHO.market(usdc).pauseStatuses.isRepayPaused);
        assertTrue(MORPHO.market(usdc).pauseStatuses.isWithdrawPaused);

        assertTrue(MORPHO.market(wbtc).pauseStatuses.isRepayPaused);
        assertTrue(MORPHO.market(wbtc).pauseStatuses.isWithdrawPaused);
    }
}
