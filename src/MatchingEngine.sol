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
                step: _promote
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
                step: _promote
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
                step: _demote
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
                step: _demote
            })
        );
    }

    function _promoteOrDemote(
        ThreeHeapOrdering.HeapArray storage heapOnPool,
        ThreeHeapOrdering.HeapArray storage heapInP2P,
        Types.PromoteVars memory vars
    ) internal returns (uint256 promoted, uint256 loopsDone) {
        if (vars.maxLoops == 0) return (0, 0);

        uint256 remaining = vars.amount;
        ThreeHeapOrdering.HeapArray storage workingHeap = vars.promoting ? heapOnPool : heapInP2P;
        function (address, address, uint256, uint256) internal _updateDS =
            vars.borrow ? _updateBorrowerInDS : _updateSupplierInDS;

        for (; loopsDone < vars.maxLoops; ++loopsDone) {
            address firstUser = workingHeap.getHead();
            if (firstUser == address(0)) break;

            uint256 onPool;
            uint256 inP2P;

            (onPool, inP2P, remaining) = vars.step(
                heapOnPool.getValueOf(firstUser),
                heapInP2P.getValueOf(firstUser),
                vars.poolIndex,
                vars.p2pIndex,
                remaining
            );

            _updateDS(vars.poolToken, firstUser, onPool, inP2P);
            emit Events.PositionUpdated(vars.borrow, firstUser, vars.poolToken, onPool, inP2P);
        }

        // Safe unchecked because vars.amount >= remaining.
        unchecked {
            promoted = vars.amount - remaining;
        }
    }

    function _promote(uint256 poolBalance, uint256 p2pBalance, uint256 poolIndex, uint256 p2pIndex, uint256 remaining)
        internal
        pure
        returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining)
    {
        uint256 toProcess = Math.min(poolBalance.rayMul(poolIndex), remaining);
        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance - toProcess.rayDiv(poolIndex);
        newP2PBalance = p2pBalance + toProcess.rayDiv(p2pIndex);
    }

    function _demote(uint256 poolBalance, uint256 p2pBalance, uint256 poolIndex, uint256 p2pIndex, uint256 remaining)
        internal
        pure
        returns (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining)
    {
        uint256 toProcess = Math.min(p2pBalance.rayMul(p2pIndex), remaining);
        newRemaining = remaining - toProcess;
        newPoolBalance = poolBalance + toProcess.rayDiv(poolIndex);
        newP2PBalance = p2pBalance - toProcess.rayDiv(p2pIndex);
    }
}
