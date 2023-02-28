// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Morpho} from "src/Morpho.sol";

import "./ForkTest.sol";

contract InternalTest is ForkTest, Morpho {
    using TestConfigLib for TestConfig;

    function setUp() public virtual override {
        super.setUp();

        _addressesProvider = IPoolAddressesProvider(_initConfig().getAddressesProvider());
        _pool = IPool(_addressesProvider.getPool());
    }
}
