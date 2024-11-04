// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IStableDebtTokenLegacy {
    function getSupplyData() external view returns (uint256, uint256, uint256, uint40);
}
