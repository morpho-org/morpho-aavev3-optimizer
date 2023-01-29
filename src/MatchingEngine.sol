// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";

import {MarketLib} from "./libraries/MarketLib.sol";
import {LogarithmicBuckets} from "@morpho-data-structures/LogarithmicBuckets.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

/// @title MatchingEngine
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Abstract contract with functions to promote or demote users to/from peer-to-peer.
abstract contract MatchingEngine is MorphoInternal {
    using MarketLib for Types.Market;
    using LogarithmicBuckets for LogarithmicBuckets.BucketList;

    using Math for uint256;
    using WadRayMath for uint256;

    /// @dev Demotes suppliers on the `underlying` market.
    /// @param underlying The address of the underlying market on which to promote suppliers.
    /// @param amount The amount of `underlying` to promote.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    function _promoteSuppliers(address underlying, uint256 amount, uint256 maxIterations)
        internal
        returns (uint256 promoted, uint256 iterationsDone)
    {
        return _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: _market[underlying].getSupplyIndexes(),
                amount: amount,
                maxIterations: maxIterations,
                borrow: false,
                updateDS: _updateSupplierInDS,
                demoting: false,
                step: _promote
            })
        );
    }

    /// @dev Promotes borrowers on the `underlying` market.
    /// @param underlying The address of the underlying market on which to promote borrowers.
    /// @param amount The amount of `underlying` to promote.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    function _promoteBorrowers(address underlying, uint256 amount, uint256 maxIterations)
        internal
        returns (uint256 promoted, uint256 iterationsDone)
    {
        return _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: _market[underlying].getBorrowIndexes(),
                amount: amount,
                maxIterations: maxIterations,
                borrow: true,
                updateDS: _updateBorrowerInDS,
                demoting: false,
                step: _promote
            })
        );
    }

    /// @dev Demotes suppliers on the `underlying` market.
    /// @param underlying The address of the underlying market on which to demote suppliers.
    /// @param amount The amount of `underlying` to demote.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    function _demoteSuppliers(address underlying, uint256 amount, uint256 maxIterations)
        internal
        returns (uint256 demoted)
    {
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: _market[underlying].getSupplyIndexes(),
                amount: amount,
                maxIterations: maxIterations,
                borrow: false,
                updateDS: _updateSupplierInDS,
                demoting: true,
                step: _demote
            })
        );
    }

    /// @dev Demotes borrowers on the `underlying` market.
    /// @param underlying The address of the underlying market on which to demote borrowers.
    /// @param amount The amount of `underlying` to demote.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    function _demoteBorrowers(address underlying, uint256 amount, uint256 maxIterations)
        internal
        returns (uint256 demoted)
    {
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                indexes: _market[underlying].getBorrowIndexes(),
                amount: amount,
                maxIterations: maxIterations,
                borrow: true,
                updateDS: _updateBorrowerInDS,
                demoting: true,
                step: _demote
            })
        );
    }

    /// @dev Promotes or demotes users.
    /// @param poolBuckets The pool buckets.
    /// @param poolBuckets The peer-to-peer buckets.
    /// @param vars The required matching engine variables to perform the matching process.
    function _promoteOrDemote(
        LogarithmicBuckets.BucketList storage poolBuckets,
        LogarithmicBuckets.BucketList storage p2pBuckets,
        Types.MatchingEngineVars memory vars
    ) internal returns (uint256 processed, uint256 iterationsDone) {
        if (vars.maxIterations == 0) return (0, 0);

        uint256 remaining = vars.amount;
        LogarithmicBuckets.BucketList storage workingBuckets = vars.demoting ? p2pBuckets : poolBuckets;

        for (; iterationsDone < vars.maxIterations && remaining != 0; ++iterationsDone) {
            address firstUser = workingBuckets.getMatch(remaining);
            if (firstUser == address(0)) break;

            Types.BalanceVars memory bal;
            bal.formerOnPool = poolBuckets.getValueOf(firstUser);
            bal.formerInP2P = p2pBuckets.getValueOf(firstUser);

            (bal.newOnPool, bal.newInP2P, remaining) =
                vars.step(bal.formerOnPool, bal.formerInP2P, vars.indexes, remaining);

            vars.updateDS(
                vars.underlying,
                firstUser,
                bal.formerOnPool,
                bal.formerInP2P,
                bal.newOnPool,
                bal.newInP2P,
                vars.demoting
            );

            if (vars.borrow) emit Events.BorrowPositionUpdated(firstUser, vars.underlying, bal.newOnPool, bal.newInP2P);
            else emit Events.SupplyPositionUpdated(firstUser, vars.underlying, bal.newOnPool, bal.newInP2P);
        }

        // Safe unchecked because vars.amount >= remaining.
        unchecked {
            processed = vars.amount - remaining;
        }
    }

    /// @dev Promotes a given amount in peer-to-peer.
    /// @param poolBalance The scaled balance of the user on the pool.
    /// @param p2pBalance The scaled balance of the user in peer-to-peer.
    /// @param indexes The indexes of the market.
    /// @param remaining The remaining amount to promote.
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

    /// @dev Demotes a given amount in peer-to-peer.
    /// @param poolBalance The scaled balance of the user on the pool.
    /// @param p2pBalance The scaled balance of the user in peer-to-peer.
    /// @param indexes The indexes of the market.
    /// @param remaining The remaining amount to demote.
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
