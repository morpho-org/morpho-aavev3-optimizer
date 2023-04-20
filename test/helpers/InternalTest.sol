// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Morpho} from "src/Morpho.sol";

import "./ForkTest.sol";

contract InternalTest is ForkTest, Morpho {
    using ConfigLib for Config;

    address internal constant POSITIONS_MANAGER = address(0xCA11);
    bytes32 internal constant INITIALIZED_SLOT = bytes32(uint256(57));

    function setUp() public virtual override {
        super.setUp();

        vm.store(address(this), INITIALIZED_SLOT, 0); // Re-enable initialization.
        this.initialize(
            config.getAddressesProvider(),
            uint8(vm.envOr("E_MODE_CATEGORY_ID", uint256(0))),
            POSITIONS_MANAGER,
            Types.Iterations({repay: 10, withdraw: 10})
        );
    }
}
