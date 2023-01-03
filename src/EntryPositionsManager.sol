// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "./interfaces/aave/IPool.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {PoolLib} from "./libraries/PoolLib.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";

contract EntryPositionsManager is PositionsManagerInternal {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;
    using PoolLib for IPool;

    function supplyLogic(address underlying, uint256 amount, address from, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        _validateSupply(underlying, amount, onBehalf);

        ERC20(underlying).safeTransferFrom(from, address(this), amount);

        (uint256 onPool, uint256 inP2P, uint256 toRepay, uint256 toSupply) =
            _executeSupply(underlying, amount, onBehalf, maxLoops, indexes);

        if (toRepay > 0) _pool.repayToPool(underlying, _market[underlying].variableDebtToken, toRepay);
        if (toSupply > 0) _pool.supplyToPool(underlying, toSupply);

        emit Events.Supplied(from, onBehalf, underlying, amount, onPool, inP2P);
        return amount;
    }

    function supplyCollateralLogic(address underlying, uint256 amount, address from, address onBehalf)
        external
        returns (uint256 supplied)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        _validateSupplyCollateral(underlying, amount, onBehalf);

        ERC20(underlying).safeTransferFrom(from, address(this), amount);

        _marketBalances[underlying].collateral[onBehalf] += amount.rayDiv(indexes.supply.poolIndex);

        _pool.supplyToPool(underlying, amount);

        emit Events.CollateralSupplied(
            from, onBehalf, underlying, amount, _marketBalances[underlying].collateral[onBehalf]
            );
        return amount;
    }

    function borrowLogic(address underlying, uint256 amount, address borrower, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        _validateBorrow(underlying, amount, borrower);

        (uint256 onPool, uint256 inP2P, uint256 toWithdraw, uint256 toBorrow) =
            _executeBorrow(underlying, amount, borrower, maxLoops, indexes);

        if (toWithdraw > 0) _pool.withdrawFromPool(underlying, _market[underlying].aToken, toWithdraw);
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Borrowed(borrower, underlying, amount, onPool, inP2P);
        return amount;
    }
}
