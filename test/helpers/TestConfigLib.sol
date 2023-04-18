// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {stdJson} from "@forge-std/StdJson.sol";

struct TestConfig {
    string json;
}

library TestConfigLib {
    using stdJson for string;

    string internal constant RPC_ALIAS_PATH = "$.rpcAlias";
    string internal constant FORK_BLOCK_NUMBER_PATH = "$.forkBlockNumber";
    string internal constant ADDRESSES_PROVIDER_PATH = "$.addressesProvider";
    string internal constant WRAPPED_NATIVE_PATH = "$.wrappedNative";
    string internal constant LSD_NATIVES_PATH = "$.lsdNatives";
    string internal constant MARKETS_PATH = "$.markets";
    string internal constant MORPHO_DAO_PATH = "$.morphoDao";
    string internal constant REWARDS_CONTROLLER_PATH = "$.rewardsController";

    function getAddress(TestConfig storage config, string memory key) internal returns (address) {
        return config.json.readAddress(string.concat("$.", key));
    }

    function getAddressArray(TestConfig storage config, string[] memory keys)
        internal
        returns (address[] memory addresses)
    {
        addresses = new address[](keys.length);

        for (uint256 i; i < keys.length; ++i) {
            addresses[i] = getAddress(config, keys[i]);
        }
    }

    function getRpcAlias(TestConfig storage config) internal returns (string memory) {
        return config.json.readString(RPC_ALIAS_PATH);
    }

    function getForkBlockNumber(TestConfig storage config) internal returns (uint256) {
        return config.json.readUint(FORK_BLOCK_NUMBER_PATH);
    }

    function getAddressesProvider(TestConfig storage config) internal returns (address) {
        return config.json.readAddress(ADDRESSES_PROVIDER_PATH);
    }

    function getMorphoDao(TestConfig storage config) internal returns (address) {
        return config.json.readAddress(MORPHO_DAO_PATH);
    }

    function getRewardsController(TestConfig storage config) internal returns (address) {
        return config.json.readAddress(REWARDS_CONTROLLER_PATH);
    }

    function getWrappedNative(TestConfig storage config) internal returns (address) {
        return getAddress(config, config.json.readString(WRAPPED_NATIVE_PATH));
    }

    function getLsdNatives(TestConfig storage config) internal returns (address[] memory) {
        return getAddressArray(config, config.json.readStringArray(LSD_NATIVES_PATH));
    }
}
