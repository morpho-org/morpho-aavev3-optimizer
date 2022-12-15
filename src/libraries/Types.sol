// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";

library Types {
    /// ENUMS ///

    enum SupplyType {
        PURE,
        COLLATERAL
    }

    /// STRUCTS ///

    struct Market {
        mapping(address => ThreeHeapOrdering.HeapArray) suppliersP2P;
        mapping(address => ThreeHeapOrdering.HeapArray) suppliersPool;
        mapping(address => ThreeHeapOrdering.HeapArray) borrowersP2P;
        mapping(address => ThreeHeapOrdering.HeapArray) borrowersPool;
    }
}
