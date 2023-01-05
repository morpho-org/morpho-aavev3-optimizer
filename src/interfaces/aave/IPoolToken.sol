// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IPoolToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
