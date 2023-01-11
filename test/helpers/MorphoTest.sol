// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Morpho} from "../../src/Morpho.sol";

import "./ForkTest.sol";

contract MorphoTest is ForkTest, Morpho {
    using TestConfigLib for TestConfig;

    constructor() Morpho(_initConfig().getAddress("addressesProvider")) {}
}
