// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types, Events, ThreeHeapOrdering, Math, WadRayMath} from "./libraries/Libraries.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MatchingEngine is MorphoInternal {
    using Math for uint256;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using WadRayMath for uint256;

    function _promoteSuppliers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Market storage market = _market[poolToken];
        return _promoteOrDemote(
            _marketBalances[poolToken].poolSuppliers,
            _marketBalances[poolToken].p2pSuppliers,
            Types.PromoteVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolSupplyIndex,
                p2pIndex: market.indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                promoting: true,
                f: _promoteStep
            })
        );
    }

    function _promoteBorrowers(address poolToken, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Market storage market = _market[poolToken];
        return _promoteOrDemote(
            _marketBalances[poolToken].poolBorrowers,
            _marketBalances[poolToken].p2pBorrowers,
            Types.PromoteVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolBorrowIndex,
                p2pIndex: market.indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                promoting: true,
                f: _promoteStep
            })
        );
    }

    function _demoteSuppliers(address poolToken, uint256 amount, uint256 maxLoops) internal returns (uint256 demoted) {
        Types.Market storage market = _market[poolToken];
        (demoted,) = _promoteOrDemote(
            _marketBalances[poolToken].poolSuppliers,
            _marketBalances[poolToken].p2pSuppliers,
            Types.PromoteVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolSupplyIndex,
                p2pIndex: market.indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                promoting: false,
                f: _demoteStep
            })
        );
    }

    function _demoteBorrowers(address poolToken, uint256 amount, uint256 maxLoops) internal returns (uint256 demoted) {
        Types.Market storage market = _market[poolToken];
        (demoted,) = _promoteOrDemote(
            _marketBalances[poolToken].poolBorrowers,
            _marketBalances[poolToken].p2pBorrowers,
            Types.PromoteVars({
                poolToken: poolToken,
                poolIndex: market.indexes.poolBorrowIndex,
                p2pIndex: market.indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                promoting: false,
                f: _demoteStep
            })
        );
    }

    function _promoteOrDemote(
        ThreeHeapOrdering.HeapArray storage heapOnPool,
        ThreeHeapOrdering.HeapArray storage heapInP2P,
        Types.PromoteVars memory vars
    ) internal returns (uint256 promoted, uint256 loopsDone) {
        if (vars.maxLoops == 0) return (0, 0);

        uint256 remainingToPromote = vars.amount;
        ThreeHeapOrdering.HeapArray storage workingHeap = vars.promoting ? heapOnPool : heapInP2P;

        for (; loopsDone < vars.maxLoops; ++loopsDone) {
            address firstUser = workingHeap.getHead();
            if (firstUser == address(0)) break;

            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remainingToPromote) = vars.f(
                heapOnPool.getValueOf(firstUser),
                heapInP2P.getValueOf(firstUser),
                vars.poolIndex,
                vars.p2pIndex,
                remainingToPromote
            );

            if (!vars.borrow) {
                _updateSupplierInDS(vars.poolToken, firstUser, onPool, inP2P);
            } else {
                _updateBorrowerInDS(vars.poolToken, firstUser, onPool, inP2P);
            }

            emit Events.PositionUpdated(vars.borrow, firstUser, vars.poolToken, onPool, inP2P);
        }

        // Safe unchecked because vars.amount >= remainingToPromote.
        unchecked {
            promoted = vars.amount - remainingToPromote;
        }
    }

    function _promoteStep(
        uint256 poolBalance,
        uint256 p2pBalance,
        uint256 poolIndex,
        uint256 p2pIndex,
        uint256 remaining
    ) internal pure returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining) {
        uint256 toProcess = Math.min(poolBalance.rayMul(poolIndex), remaining);
        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance - toProcess.rayDiv(poolIndex);
        newP2PBalance = p2pBalance + toProcess.rayDiv(p2pIndex);
    }

    function _demoteStep(
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
