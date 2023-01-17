// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";

import {MarketLib} from "./libraries/MarketLib.sol";
import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MatchingEngine is MorphoInternal {
    using MarketLib for Types.Market;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;

    using Math for uint256;
    using WadRayMath for uint256;

    function _promoteSuppliers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Market storage market = _market[underlying];
        return _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: market.getSupplyIndexes(),
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                updateDS: _moveSupplierInDS,
                demoting: false,
                step: _promote
            })
        );
    }

    function _promoteBorrowers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Market storage market = _market[underlying];
        return _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: market.getBorrowIndexes(),
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                updateDS: _moveBorrowerInDS,
                demoting: false,
                step: _promote
            })
        );
    }

    function _demoteSuppliers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 demoted)
    {
        Types.Market storage market = _market[underlying];
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: market.getSupplyIndexes(),
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                updateDS: _moveSupplierInDS,
                demoting: true,
                step: _demote
            })
        );
    }

    function _demoteBorrowers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 demoted)
    {
        Types.Market storage market = _market[underlying];
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: market.getBorrowIndexes(),
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                updateDS: _moveBorrowerInDS,
                demoting: true,
                step: _demote
            })
        );
    }

    function _promoteOrDemote(
        LogarithmicBuckets.BucketList storage poolBuckets,
        LogarithmicBuckets.BucketList storage p2pBuckets,
        Types.MatchingEngineVars memory vars
    ) internal returns (uint256 processed, uint256 loopsDone) {
        if (vars.maxLoops == 0) return (0, 0);

        uint256 remaining = vars.amount;
        LogarithmicBuckets.BucketList storage workingBuckets = vars.demoting ? p2pBuckets : poolBuckets;

        for (; loopsDone < vars.maxLoops && remaining != 0; ++loopsDone) {
            address firstUser = workingBuckets.getMatch(remaining);
            if (firstUser == address(0)) break;

            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remaining) =
                vars.step(poolBuckets.getValueOf(firstUser), p2pBuckets.getValueOf(firstUser), vars.indexes, remaining);

            vars.updateDS(vars.underlying, firstUser, onPool, inP2P, vars.demoting);
            emit Events.PositionUpdated(vars.borrow, firstUser, vars.underlying, onPool, inP2P);
        }

        // Safe unchecked because vars.amount >= remaining.
        unchecked {
            processed = vars.amount - remaining;
        }
    }

    function _promote(
        uint256 poolBalance,
        uint256 p2pBalance,
        Types.MarketSideIndexes256 memory indexes,
        uint256 remaining
    ) internal pure returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining) {
        uint256 toProcess = Math.min(poolBalance.rayMul(indexes.poolIndex), remaining);

        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance - toProcess.rayDiv(indexes.poolIndex);
        newP2PBalance = p2pBalance + toProcess.rayDiv(indexes.p2pIndex);
    }

    function _demote(
        uint256 poolBalance,
        uint256 p2pBalance,
        Types.MarketSideIndexes256 memory indexes,
        uint256 remaining
    ) internal pure returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining) {
        uint256 toProcess = Math.min(p2pBalance.rayMul(indexes.p2pIndex), remaining);

        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance + toProcess.rayDiv(indexes.poolIndex);
        newP2PBalance = p2pBalance - toProcess.rayDiv(indexes.p2pIndex);
    }
}
