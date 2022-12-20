// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ThreeHeapOrdering, Math, WadRayMath} from "./libraries/Libraries.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MatchingEngine is MorphoInternal {
    using Math for uint256;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using WadRayMath for uint256;

    function _matchSuppliers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 matched, uint256 loopsDone)
    {
        Types.Market storage market = _market[poolToken];
        return _matchOrUnmatch(
            _marketBalances[poolToken].poolSuppliers,
            _marketBalances[poolToken].p2pSuppliers,
            Types.MatchVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolSupplyIndex,
                p2pIndex: market.indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                matching: true
            })
        );
    }

    function _matchBorrowers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 matched, uint256 loopsDone)
    {
        Types.Market storage market = _market[poolToken];
        return _matchOrUnmatch(
            _marketBalances[poolToken].poolBorrowers,
            _marketBalances[poolToken].p2pBorrowers,
            Types.MatchVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolBorrowIndex,
                p2pIndex: market.indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                matching: true
            })
        );
    }

    function _unmatchSuppliers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 unmatched)
    {
        Types.Market storage market = _market[poolToken];
        (unmatched,) = _matchOrUnmatch(
            _marketBalances[poolToken].poolSuppliers,
            _marketBalances[poolToken].p2pSuppliers,
            Types.MatchVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolSupplyIndex,
                p2pIndex: market.indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                matching: false
            })
        );
    }

    function _unmatchBorrowers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 unmatched)
    {
        Types.Market storage market = _market[poolToken];
        (unmatched,) = _matchOrUnmatch(
            _marketBalances[poolToken].poolBorrowers,
            _marketBalances[poolToken].p2pBorrowers,
            Types.MatchVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolBorrowIndex,
                p2pIndex: market.indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                matching: false
            })
        );
    }

    function _matchOrUnmatch(
        ThreeHeapOrdering.HeapArray storage heapOnPool,
        ThreeHeapOrdering.HeapArray storage heapInP2P,
        Types.MatchVars memory vars
    ) internal returns (uint256 matched, uint256 loopsDone) {
        if (vars.maxLoops == 0) return (0, 0);

        uint256 remainingToMatch = vars.amount;

        // This function will be used to decide whether to use the algorithm for matching or for unmatching.
        function(uint256, uint256, uint256, uint256, uint256)
            pure returns (uint256, uint256, uint256) f;
        ThreeHeapOrdering.HeapArray storage workingHeap;

        if (vars.matching) {
            workingHeap = heapOnPool;
            f = _matchStep;
        } else {
            workingHeap = heapInP2P;
            f = _unmatchStep;
        }

        for (; loopsDone < vars.maxLoops; ++loopsDone) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            address firstUser = workingHeap.getHead();
            if (firstUser == address(0)) break;

            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remainingToMatch) = f(
                heapOnPool.getValueOf(firstUser),
                heapInP2P.getValueOf(firstUser),
                vars.poolIndex,
                vars.p2pIndex,
                remainingToMatch
            );

            if (!vars.borrow) {
                _updateSupplierInDS(vars.poolToken, firstUser, onPool, inP2P);
            } else {
                _updateBorrowerInDS(vars.poolToken, firstUser, onPool, inP2P);
            }

            emit Events.PositionUpdated(vars.borrow, firstUser, vars.poolToken, onPool, inP2P);
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = vars.amount - remainingToMatch;
        }
    }

    function _matchStep(uint256 poolBalance, uint256 p2pBalance, uint256 poolIndex, uint256 p2pIndex, uint256 remaining)
        internal
        pure
        returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining)
    {
        uint256 toProcess = Math.min(poolBalance.rayMul(poolIndex), remaining);
        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance - toProcess.rayDiv(poolIndex);
        newP2PBalance = p2pBalance + toProcess.rayDiv(p2pIndex);
    }

    function _unmatchStep(
        uint256 poolBalance,
        uint256 p2pBalance,
        uint256 poolIndex,
        uint256 p2pIndex,
        uint256 remaining
    ) internal pure returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining) {
        uint256 toProcess = Math.min(p2pBalance.rayMul(p2pIndex), remaining);
        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance + toProcess.rayDiv(poolIndex);
        newP2PBalance = p2pBalance - toProcess.rayDiv(p2pIndex);
    }
}
