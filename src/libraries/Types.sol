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

    /// NESTED STRUCTS ///

    struct Delta {
        uint256 p2pSupplyDelta; // Difference between the stored peer-to-peer supply amount and the real peer-to-peer supply amount (in pool supply unit).
        uint256 p2pBorrowDelta; // Difference between the stored peer-to-peer borrow amount and the real peer-to-peer borrow amount (in pool borrow unit).
        uint256 p2pSupplyAmount; // Sum of all stored peer-to-peer supply (in peer-to-peer supply unit).
        uint256 p2pBorrowAmount; // Sum of all stored peer-to-peer borrow (in peer-to-peer borrow unit).
    }

    struct PoolIndexes {
        uint32 lastUpdateTimestamp; // The last time the local pool and peer-to-peer indexes were updated.
        uint112 poolSupplyIndex; // Last pool supply index (in ray).
        uint112 poolBorrowIndex; // Last pool borrow index (in ray).
    }

    struct PauseStatuses {
        bool isP2PDisabled;
        bool isSupplyPaused;
        bool isBorrowPaused;
        bool isWithdrawPaused;
        bool isRepayPaused;
        bool isLiquidateCollateralPaused;
        bool isLiquidateBorrowPaused;
        bool isDeprecated;
    }

    /// STORAGE STRUCTS ///

    // This market struct is able to be passed into memory.
    struct Market {
        uint256 p2pSupplyIndex; // 256 bits
        uint256 p2pBorrowIndex; // 256 bits
        BorrowMask borrowMask; // 256 bits
        Delta deltas; // 1024 bits
        uint32 lastUpdateTimestamp; // 32 bits
        uint112 poolSupplyIndex; // 112 bits
        uint112 poolBorrowIndex; // 112 bits
        address underlying; // 168 bits
        address variableDebtToken; // 168 bits
        uint16 reserveFactor; // 16 bits
        uint16 p2pIndexCursor; // 16 bits
        PauseStatuses pauseStatuses; // 64 bits
    }

    // Contains storage-only dynamic arrays and mappings.
    struct MarketBalances {
        ThreeHeapOrdering.HeapArray suppliersP2P; // in scaled unit
        ThreeHeapOrdering.HeapArray suppliersPool; // in scaled unit
        ThreeHeapOrdering.HeapArray borrowersP2P; // in scaled unit
        ThreeHeapOrdering.HeapArray borrowersPool; // in scaled unit
        mapping(address => uint256) collateral; // in scaled unit
    }

    struct UserMarkets {
        bytes32 data;
    }

    struct BorrowMask {
        bytes32 data;
    }

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

    struct MatchVars {
        address poolToken;
        uint256 poolIndex;
        uint256 p2pIndex;
        uint256 amount;
        uint256 maxLoops;
        bool borrow;
        bool matching; // True for match, False for unmatch
    }

    struct IRMParams {
        uint256 lastP2PSupplyIndex; // The peer-to-peer supply index at last update.
        uint256 lastP2PBorrowIndex; // The peer-to-peer borrow index at last update.
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 lastPoolSupplyIndex; // The pool supply index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }
}
