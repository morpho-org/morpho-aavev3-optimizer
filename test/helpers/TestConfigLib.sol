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

    string public constant RPC_PATH = "$.rpc";
    string public constant CHAIN_ID_PATH = "$.chainId";
    string public constant TEST_BLOCK_PATH = "$.testBlock";
    string public constant USES_RPC_PREFIX_PATH = "$.usesRpcPrefix";
    string public constant ADDRESSES_PROVIDER_PATH = "$.addressesProvider";

    function load(TestConfig storage config, string memory network) internal returns (TestConfig storage) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/", network, ".json");

        config.json = vm.readFile(path);

        return config;
    }

    function getAddress(TestConfig storage config, string memory key) internal view returns (address) {
        return config.json.readAddress(string(abi.encodePacked(key)));
    }

    function getAddressesProvider(TestConfig storage config) internal view returns (address) {
        return getAddress(config, ADDRESSES_PROVIDER_PATH);
    }

    function createFork(TestConfig storage config) internal returns (uint256 forkId) {
        bool rpcPrefixed = stdJson.readBool(config.json, USES_RPC_PREFIX_PATH);
        string memory endpoint = rpcPrefixed
            ? string.concat(config.json.readString(RPC_PATH), vm.envString("ALCHEMY_KEY"))
            : config.json.readString(RPC_PATH);

        forkId = vm.createSelectFork(endpoint, config.json.readUint(TEST_BLOCK_PATH));
        vm.chainId(config.json.readUint(CHAIN_ID_PATH));
    }
}
