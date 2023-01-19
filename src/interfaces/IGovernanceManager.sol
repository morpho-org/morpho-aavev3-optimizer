// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IGovernanceManager {
    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external;
    function increaseP2PDeltas(address underlying, uint256 amount) external;
}
