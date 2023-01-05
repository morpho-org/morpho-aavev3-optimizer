// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

import "@forge-std/Vm.sol";
import "@forge-std/StdJson.sol";
import "@forge-std/console2.sol";

library TestHelpers {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant CONFIG_PATH = "/config/";

    function getJsonConfig(string memory network) internal view returns (string memory json) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, CONFIG_PATH, network, ".json"));
        json = vm.readFile(path);
    }

    function getAddress(string memory key) internal view returns (address) {
        string memory json = getJsonConfig(vm.envString("NETWORK"));
        return getAddressFromJson(json, key);
    }

    function getAddressFromJson(string memory json, string memory key) internal pure returns (address) {
        return json.readAddress(string(abi.encodePacked(key)));
    }

    function getTestMarkets(string memory json) internal pure returns (address[] memory) {
        string[] memory marketNames = json.readStringArray(string(abi.encodePacked("testMarkets")));
        address[] memory markets = new address[](marketNames.length);

        for (uint256 i; i < markets.length; i++) {
            markets[i] = getAddressFromJson(json, marketNames[i]);
        }
        return markets;
    }

    function setForkFromEnv() internal returns (uint256 forkId) {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }

    function setForkFromJson(string memory json) internal returns (uint256 forkId) {
        bool rpcPrefixed = stdJson.readBool(json, string(abi.encodePacked("usesRpcPrefix")));
        string memory endpoint = rpcPrefixed
            ? string(abi.encodePacked(json.readString(string(abi.encodePacked("rpc"))), vm.envString("ALCHEMY_KEY")))
            : json.readString(string(abi.encodePacked("rpc")));

        forkId = vm.createSelectFork(endpoint, json.readUint(string(abi.encodePacked("testBlock"))));
        vm.chainId(json.readUint(string(abi.encodePacked("chainId"))));
    }
}
