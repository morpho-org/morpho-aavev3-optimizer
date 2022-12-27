// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "./interfaces/Interfaces.sol";
import {MarketLib} from "./libraries/Libraries.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {PoolInteractions} from "./libraries/PoolInteractions.sol";

import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

contract EntryPositionsManager is PositionsManagerInternal {
    using MarketLib for Types.Market;
    using PoolInteractions for IPool;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    function supplyLogic(address poolToken, uint256 amount, address from, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied)
    {
        address underlying = _market[poolToken].underlying;
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);

        _validateSupply(poolToken, onBehalf, amount);

        ERC20(underlying).safeTransferFrom(from, address(this), amount);

        (uint256 onPool, uint256 inP2P, uint256 toSupply, uint256 toRepay) =
            _executeSupply(poolToken, onBehalf, amount, maxLoops, indexes);

        if (toRepay > 0) _pool.repayToPool(underlying, toRepay);
        if (toSupply > 0) _pool.supplyToPool(underlying, toSupply);

        emit Events.Supplied(from, onBehalf, poolToken, amount, onPool, inP2P);
        return amount;
    }

    function supplyCollateralLogic(address poolToken, uint256 amount, address from, address onBehalf)
        external
        returns (uint256 supplied)
    {
        address underlying = _market[poolToken].underlying;
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);

        _validateSupply(poolToken, onBehalf, amount);

        ERC20(underlying).safeTransferFrom(from, address(this), amount);

        _marketBalances[poolToken].collateral[onBehalf] += amount.rayDiv(indexes.poolSupplyIndex);

        _pool.supplyToPool(underlying, amount);

        emit Events.CollateralSupplied(
            from, onBehalf, poolToken, amount, _marketBalances[poolToken].collateral[onBehalf]
            );
        return amount;
    }

    function borrowLogic(address poolToken, uint256 amount, address borrower, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed)
    {
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);
        _validateBorrow(poolToken, borrower, amount);

        (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) =
            _executeBorrow(poolToken, borrower, amount, maxLoops, indexes);

        address underlying = _market[poolToken].underlying;
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        if (toWithdraw > 0) {
            _pool.withdrawFromPool(underlying, poolToken, toWithdraw);
        }
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Borrowed(borrower, poolToken, amount, onPool, inP2P);
        return amount;
    }
}
