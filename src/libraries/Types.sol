// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Heap} from "morpho-data-structures/ThreeHeapOrdering.sol";

library Types {
    /// ENUMS ///

    enum SupplyType {
        PURE,
        COLLATERAL
    }

    /// STRUCTS ///

    struct Market {
        mapping(address => Heap) suppliersP2P;
        mapping(address => Heap) suppliersPool;
        mapping(address => Heap) borrowersP2P;
        mapping(address => Heap) borrowersPool;
    }
}
