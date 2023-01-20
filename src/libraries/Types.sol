// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";

library Types {
    /// NESTED STRUCTS ///

    struct MarketSideDelta {
        uint256 scaledDeltaPool; // in pool unit
        uint256 scaledTotalP2P; // in p2p unit
    }

    struct Deltas {
        MarketSideDelta supply;
        MarketSideDelta borrow;
    }

    struct MarketSideIndexes {
        uint128 poolIndex;
        uint128 p2pIndex;
    }

    struct Indexes {
        MarketSideIndexes supply;
        MarketSideIndexes borrow;
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

    /// STORAGE STRUCTS ///

    // This market struct is able to be passed into memory.
    struct Market {
        // SLOT 0-1
        Indexes indexes;
        // SLOT 2-5
        Deltas deltas; // 1024 bits
        // SLOT 6
        address underlying; // 160 bits
        PauseStatuses pauseStatuses; // 80 bits
        // SLOT 7
        address variableDebtToken; // 160 bits
        uint32 lastUpdateTimestamp; // 32 bits
        uint16 reserveFactor; // 16 bits
        uint16 p2pIndexCursor; // 16 bits
        // SLOT 8
        address aToken; // 160 bits
        // SLOT 9
        uint256 idleSupply; // 256 bits
    }

    // Contains storage-only dynamic arrays and mappings.
    struct MarketBalances {
        LogarithmicBuckets.BucketList p2pSuppliers; // in scaled unit.
        LogarithmicBuckets.BucketList poolSuppliers; // in scaled unit.
        LogarithmicBuckets.BucketList p2pBorrowers; // in scaled unit.
        LogarithmicBuckets.BucketList poolBorrowers; // in scaled unit.
        mapping(address => uint256) collateral; // in scaled unit.
    }

    struct MaxLoops {
        uint64 supply;
        uint64 borrow;
        uint64 repay;
        uint64 withdraw;
    }

    /// STACK AND RETURN STRUCTS ///

    struct LiquidityData {
        uint256 collateral; // The collateral value (in base currency, 8 decimals).
        uint256 borrowable; // The maximum debt value allowed to borrow (in base currency, 8 decimals).
        uint256 maxDebt; // The maximum debt value allowed before being liquidatable (in base currency, 8 decimals).
        uint256 debt; // The debt value (in base currency, 8 decimals).
    }

    struct IndexesParams {
        MarketSideIndexes256 lastSupplyIndexes;
        MarketSideIndexes256 lastBorrowIndexes;
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Deltas deltas; // The deltas and peer-to-peer amounts.
        uint256 proportionIdle; // In ray.
    }

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in ray).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in ray).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in ray).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in ray).
    }

    struct MarketSideIndexes256 {
        uint256 poolIndex;
        uint256 p2pIndex;
    }

    struct Indexes256 {
        MarketSideIndexes256 supply;
        MarketSideIndexes256 borrow;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct MatchingEngineVars {
        address underlying;
        MarketSideIndexes256 indexes;
        uint256 amount;
        uint256 maxLoops;
        bool borrow;
        function (address, address, uint256, uint256, bool) updateDS; // This function will be used to update the data-structure.
        bool demoting; // True for demote, False for promote.
        function(uint256, uint256, MarketSideIndexes256 memory, uint256)
            pure returns (uint256, uint256, uint256) step; // This function will be used to decide whether to use the algorithm for promoting or for demoting.
    }

    struct LiquidityVars {
        address user;
        IAaveOracle oracle;
        DataTypes.EModeCategory eModeCategory;
        DataTypes.UserConfigurationMap morphoPoolConfig;
    }

    struct PromoteVars {
        address underlying;
        uint256 amount;
        uint256 poolIndex;
        uint256 maxLoops;
        function(address, uint256, uint256) returns (uint256, uint256) promote;
    }

    struct BorrowWithdrawVars {
        uint256 onPool;
        uint256 inP2P;
        uint256 toWithdraw;
        uint256 toBorrow;
    }

    struct SupplyRepayVars {
        uint256 onPool;
        uint256 inP2P;
        uint256 toSupply;
        uint256 toRepay;
    }

    struct LiquidateVars {
        uint256 closeFactor;
        uint256 amountToLiquidate;
        uint256 amountToSeize;
    }
}
