// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";

library Types {
    /// ENUMS ///

    enum PositionType {
        SUPPLY,
        COLLATERAL,
        BORROW
    }

    /// STRUCTS ///

    struct Market {
        ThreeHeapOrdering.HeapArray suppliersP2P;
        ThreeHeapOrdering.HeapArray suppliersPool;
        ThreeHeapOrdering.HeapArray borrowersP2P;
        ThreeHeapOrdering.HeapArray borrowersPool;
        mapping(address => uint256) collateralScaledBalance;
    }
}
