// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Vm} from "@forge-std/Vm.sol";
import {stdJson} from "@forge-std/StdJson.sol";

struct TestConfig {
    string json;
}

library TestConfigLib {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function load(TestConfig storage config, string memory network) internal returns (TestConfig storage) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/config/", network, ".json"));

        config.json = vm.readFile(path);

        return config;
    }

    function getAddress(TestConfig storage config, string memory key) internal view returns (address) {
        return config.json.readAddress(string(abi.encodePacked(key)));
    }

    function getTestMarkets(TestConfig storage config) internal view returns (address[] memory) {
        string[] memory marketNames = config.json.readStringArray(string(abi.encodePacked("testMarkets")));
        address[] memory markets = new address[](marketNames.length);

        for (uint256 i; i < markets.length; i++) {
            markets[i] = getAddress(config, marketNames[i]);
        }

        return markets;
    }

    function createFork(TestConfig storage config) internal returns (uint256 forkId) {
        bool rpcPrefixed = stdJson.readBool(config.json, string(abi.encodePacked("usesRpcPrefix")));
        string memory endpoint = rpcPrefixed
            ? string(abi.encodePacked(config.json.readString(string(abi.encodePacked("rpc"))), vm.envString("ALCHEMY_KEY")))
            : config.json.readString(string(abi.encodePacked("rpc")));

        forkId = vm.createSelectFork(endpoint, config.json.readUint(string(abi.encodePacked("testBlock"))));
        vm.chainId(config.json.readUint(string(abi.encodePacked("chainId"))));
    }
}
