// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

library Types {
    /// ENUMS ///

    enum PositionType {
        SUPPLY,
        COLLATERAL,
        BORROW
    }

    /// NESTED STRUCTS ///

    struct Delta {
        uint256 p2pSupplyDelta; // Difference between the stored peer-to-peer supply amount and the real peer-to-peer supply amount (in pool supply unit).
        uint256 p2pBorrowDelta; // Difference between the stored peer-to-peer borrow amount and the real peer-to-peer borrow amount (in pool borrow unit).
        uint256 p2pSupplyAmount; // Sum of all stored peer-to-peer supply (in peer-to-peer supply unit).
        uint256 p2pBorrowAmount; // Sum of all stored peer-to-peer borrow (in peer-to-peer borrow unit).
    }

    struct PauseStatuses {
        bool isP2PDisabled;
        bool isSupplyPaused;
        bool isSupplyCollateralPaused;
        bool isBorrowPaused;
        bool isWithdrawPaused;
        bool isWithdrawCollateralPaused;
        bool isRepayPaused;
        bool isLiquidateCollateralPaused;
        bool isLiquidateBorrowPaused;
        bool isDeprecated;
    }

    struct Indexes {
        uint128 poolSupplyIndex;
        uint128 poolBorrowIndex;
        uint128 p2pSupplyIndex;
        uint128 p2pBorrowIndex;
    }

    /// STORAGE STRUCTS ///

    // This market struct is able to be passed into memory.
    struct Market {
        // SLOT 0-1
        Indexes indexes;
        // SLOT 2-5
        Delta deltas; // 1024 bits
        // SLOT 6
        address underlying; // 160 bits
        PauseStatuses pauseStatuses; // 64 bits
        // SLOT 7
        address variableDebtToken; // 160 bits
        uint32 lastUpdateTimestamp; // 32 bits
        uint16 reserveFactor; // 16 bits
        uint16 p2pIndexCursor; // 16 bits
    }

    // Contains storage-only dynamic arrays and mappings.
    struct MarketBalances {
        ThreeHeapOrdering.HeapArray p2pSuppliers; // in scaled unit
        ThreeHeapOrdering.HeapArray poolSuppliers; // in scaled unit
        ThreeHeapOrdering.HeapArray p2pBorrowers; // in scaled unit
        ThreeHeapOrdering.HeapArray poolBorrowers; // in scaled unit
        mapping(address => uint256) collateral; // in scaled unit
    }

    struct MaxLoopsForMatching {
        uint64 supply;
        uint64 borrow;
        uint64 repay;
        uint64 withdraw;
    }

    /// STACK AND RETURN STRUCTS ///

    struct AssetLiquidityData {
        uint256 decimals; // The number of decimals of the underlying token.
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
        uint256 ltv; // The LTV applied on this token (in basis point).
        uint256 underlyingPrice; // The price of the token (In base currency in wad).
    }

    struct LiquidityData {
        uint256 collateral; // The collateral value (In base currency in wad).
        uint256 maxDebt; // The max debt value (In base currency in wad).
        uint256 liquidationThresholdValue; // The liquidation threshold value (In base currency in wad).
        uint256 debt; // The debt value (In base currency in wad).
    }

    struct PromoteVars {
        address poolToken;
        uint256 poolIndex;
        uint256 p2pIndex;
        uint256 amount;
        uint256 maxLoops;
        bool borrow;
        function (address, address, uint256, uint256) updateDS; // This function will be used to update the data-structure.
        bool promoting; // True for promote, False for demote
        function(uint256, uint256, uint256, uint256, uint256)
            pure returns (uint256, uint256, uint256) step; // This function will be used to decide whether to use the algorithm for promoting or for demoting.
    }

    struct IRMParams {
        uint256 lastPoolSupplyIndex;
        uint256 lastPoolBorrowIndex;
        uint256 lastP2PSupplyIndex;
        uint256 lastP2PBorrowIndex;
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Delta deltas; // The deltas and peer-to-peer amounts.
    }

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in ray).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in ray).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in ray).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in ray).
    }

    struct IndexesMem {
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
    }
}
