// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IPoolAddressesProvider {
    function getPool() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getPriceOracleSentinel() external view returns (address);
}
