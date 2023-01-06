// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "@forge-std/Vm.sol";

library TestHelpers {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function createForkFromEnv() internal returns (uint256 forkId) {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }
}
