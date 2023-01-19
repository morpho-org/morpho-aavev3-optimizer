// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {MorphoInternal, MorphoStorage} from "./MorphoInternal.sol";
import {IGovernanceManager} from "./interfaces/IGovernanceManager.sol";

contract GovernanceManager is IGovernanceManager, MorphoInternal {
    constructor(address addressesProvider, uint8 eModeCategoryId) MorphoStorage(addressesProvider, eModeCategoryId) {}

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external {
        _createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function increaseP2PDeltas(address underlying, uint256 amount) external {
        _increaseP2PDeltas(underlying, amount);
    }
}
