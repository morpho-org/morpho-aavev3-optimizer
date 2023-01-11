// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from "../../src/interfaces/aave/IPool.sol";

contract MockPriceOracleSentinel {
    bool internal borrowAllowed;
    bool internal liquidationAllowed;
    address internal poolAddressesProvider;

    constructor(address addr) {
        poolAddressesProvider = addr;
    }

    function isBorrowAllowed() external view returns (bool) {
        return borrowAllowed;
    }

    function setBorrowAllowed(bool allowed) external {
        borrowAllowed = allowed;
    }

    function isLiquidationAllowed() external view returns (bool) {
        return liquidationAllowed;
    }

    function setLiquidationAllowed(bool allowed) external {
        liquidationAllowed = allowed;
    }

    function getGracePeriod() external pure returns (uint256) {
        return type(uint256).max;
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(poolAddressesProvider);
    }
}
