// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {stdJson} from "@forge-std/StdJson.sol";

struct Config {
    string json;
}

library ConfigLib {
    using stdJson for string;

    string internal constant RPC_ALIAS_PATH = "$.rpcAlias";
    string internal constant FORK_BLOCK_NUMBER_PATH = "$.forkBlockNumber";
    string internal constant ADDRESSES_PROVIDER_PATH = "$.addressesProvider";
    string internal constant WRAPPED_NATIVE_PATH = "$.wrappedNative";
    string internal constant STAKED_NATIVE_PATH = "$.stakedNative";
    string internal constant MARKETS_PATH = "$.markets";
    string internal constant MORPHO_DAO_PATH = "$.morphoDao";
    string internal constant REWARDS_CONTROLLER_PATH = "$.rewardsController";

    function getAddress(Config storage config, string memory key) internal returns (address) {
        return config.json.readAddress(string.concat("$.", key));
    }

    function getRpcAlias(Config storage config) internal returns (string memory) {
        return config.json.readString(RPC_ALIAS_PATH);
    }

    function getForkBlockNumber(Config storage config) internal returns (uint256) {
        return config.json.readUint(FORK_BLOCK_NUMBER_PATH);
    }

    function getAddressesProvider(Config storage config) internal returns (address) {
        return config.json.readAddress(ADDRESSES_PROVIDER_PATH);
    }

    function getMorphoDao(Config storage config) internal returns (address) {
        return config.json.readAddress(MORPHO_DAO_PATH);
    }

    function getRewardsController(Config storage config) internal returns (address) {
        return config.json.readAddress(REWARDS_CONTROLLER_PATH);
    }

    function getWrappedNative(Config storage config) internal returns (address) {
        return getAddress(config, config.json.readString(WRAPPED_NATIVE_PATH));
    }

    function getStakedNative(Config storage config) internal returns (address) {
        return getAddress(config, config.json.readString(STAKED_NATIVE_PATH));
    }
}
