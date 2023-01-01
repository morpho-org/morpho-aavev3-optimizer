// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

import "@forge-std/Vm.sol";
import "@forge-std/StdJson.sol";
import "@forge-std/console2.sol";

library TestHelpers {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant CONFIG_PATH = "/config/Config.json";

    function getJsonConfig() internal view returns (string memory json) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, CONFIG_PATH));
        json = vm.readFile(path);
    }

    function getAddressFromJson(string memory json, string memory network, string memory key)
        internal
        pure
        returns (address)
    {
        return json.readAddress(string(abi.encodePacked(network, ".", key)));
    }

    function getTestMarkets(string memory json, string memory network) internal pure returns (address[] memory) {
        string[] memory marketNames = json.readStringArray(string(abi.encodePacked(network, ".testMarkets")));
        address[] memory markets = new address[](marketNames.length);

        for (uint256 i; i < markets.length; i++) {
            markets[i] = getAddressFromJson(json, network, marketNames[i]);
        }
        return markets;
    }

    function setForkFromEnv() internal returns (uint256 forkId) {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }

    function setForkFromJson(string memory json, string memory network) internal returns (uint256 forkId) {
        bool rpcPrefixed = stdJson.readBool(json, string(abi.encodePacked(network, ".usesRpcPrefix")));
        string memory endpoint = rpcPrefixed
            ? string(
                abi.encodePacked(json.readString(string(abi.encodePacked(network, ".rpc"))), vm.envString("ALCHEMY_KEY"))
            )
            : json.readString(string(abi.encodePacked(network, ".rpc")));

        forkId = vm.createSelectFork(endpoint, json.readUint(string(abi.encodePacked(network, ".", "testBlock"))));
        vm.chainId(json.readUint(string(abi.encodePacked(network, ".chainId"))));
    }
}
