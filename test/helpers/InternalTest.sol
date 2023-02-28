// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Morpho} from "src/Morpho.sol";

import "./ForkTest.sol";

contract InternalTest is ForkTest, Morpho {
    using TestConfigLib for TestConfig;

    constructor() Morpho(_initConfig().getAddressesProvider(), uint8(vm.envOr("E_MODE_CATEGORY_ID", uint256(0)))) {}
}
