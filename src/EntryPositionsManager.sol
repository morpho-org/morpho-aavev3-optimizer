// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types, Events, Errors, MarketLib, ThreeHeapOrdering, PoolInteractions} from "./libraries/Libraries.sol";
import {IPool} from "./interfaces/Interfaces.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

contract EntryPositionsManager is PositionsManagerInternal {
    using MarketLib for Types.Market;
    using PoolInteractions for IPool;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using SafeTransferLib for ERC20;

    function supplyLogic(address poolToken, address from, address onBehalf, uint256 amount, uint256 maxLoops)
        external
    {
        address underlying = _market[poolToken].underlying;
        Types.IndexesMem memory indexes = _updateIndexes(poolToken);

        ERC20(underlying).safeTransferFrom(from, address(this), amount);

        _validateSupply(poolToken, onBehalf, amount);

        (uint256 onPool, uint256 inP2P, uint256 toSupply, uint256 toRepay) =
            _executeSupply(poolToken, onBehalf, amount, indexes, maxLoops);

        if (toRepay > 0) _pool.repayToPool(underlying, toRepay);
        if (toSupply > 0) _pool.supplyToPool(underlying, toSupply);

        emit Events.Supplied(from, onBehalf, poolToken, amount, onPool, inP2P);
    }

    function borrowLogic(address poolToken, uint256 amount, uint256 maxLoops) external {
        Types.IndexesMem memory indexes = _updateIndexes(poolToken);
        _validateBorrow(poolToken, msg.sender, amount);

        (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) =
            _executeBorrow(poolToken, msg.sender, amount, indexes, maxLoops);

        address underlying = _market[poolToken].underlying;
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        if (toWithdraw > 0) {
            _pool.withdrawFromPool(underlying, poolToken, toWithdraw);
        }
        ERC20(underlying).safeTransfer(msg.sender, amount);

        emit Events.Borrowed(msg.sender, poolToken, amount, onPool, inP2P);
    }
}
