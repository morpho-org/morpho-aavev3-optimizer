// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";

import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoInternal} from "./MorphoInternal.sol";

abstract contract MatchingEngine is MorphoInternal {
    using Math for uint256;
    using WadRayMath for uint256;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    function _promoteSuppliers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Indexes memory indexes = _market[underlying].indexes;
        return _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                updateDS: _updateSupplierInDS,
                promoting: true,
                step: _promote
            })
        );
    }

    function _promoteBorrowers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 promoted, uint256 loopsDone)
    {
        Types.Indexes memory indexes = _market[underlying].indexes;
        return _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                updateDS: _updateBorrowerInDS,
                promoting: true,
                step: _promote
            })
        );
    }

    function _demoteSuppliers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 demoted)
    {
        Types.Indexes memory indexes = _market[underlying].indexes;
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolSuppliers,
            _marketBalances[underlying].p2pSuppliers,
            Types.MatchingEngineVars({
                underlying: underlying,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: false,
                updateDS: _updateSupplierInDS,
                promoting: false,
                step: _demote
            })
        );
    }

    function _demoteBorrowers(address underlying, uint256 amount, uint256 maxLoops)
        internal
        returns (uint256 demoted)
    {
        Types.Indexes memory indexes = _market[underlying].indexes;
        (demoted,) = _promoteOrDemote(
            _marketBalances[underlying].poolBorrowers,
            _marketBalances[underlying].p2pBorrowers,
            Types.MatchingEngineVars({
                underlying: underlying,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                amount: amount,
                maxLoops: maxLoops,
                borrow: true,
                updateDS: _updateBorrowerInDS,
                promoting: false,
                step: _demote
            })
        );
    }

    function _promoteOrDemote(
        ThreeHeapOrdering.HeapArray storage heapOnPool,
        ThreeHeapOrdering.HeapArray storage heapInP2P,
        Types.MatchingEngineVars memory vars
    ) internal returns (uint256 processed, uint256 loopsDone) {
        if (vars.maxLoops == 0) return (0, 0);

        uint256 remaining = vars.amount;
        ThreeHeapOrdering.HeapArray storage workingHeap = vars.promoting ? heapOnPool : heapInP2P;

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

            vars.updateDS(vars.underlying, firstUser, onPool, inP2P);
            emit Events.PositionUpdated(vars.borrow, firstUser, vars.underlying, onPool, inP2P);
        }

        // Safe unchecked because vars.amount >= remaining.
        unchecked {
            processed = vars.amount - remaining;
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
