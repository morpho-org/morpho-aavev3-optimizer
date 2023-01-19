// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IPositionsManager} from "./interfaces/IPositionsManager.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {PoolLib} from "./libraries/PoolLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {Permit2Lib} from "./libraries/Permit2Lib.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MorphoStorage} from "./MorphoStorage.sol";
import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";

contract PositionsManager is IPositionsManager, PositionsManagerInternal {
    using PoolLib for IPool;
    using Permit2Lib for ERC20;
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using MarketBalanceLib for Types.MarketBalances;
    using EnumerableSet for EnumerableSet.AddressSet;

    using Math for uint256;
    using PercentageMath for uint256;

    /// CONSTRUCTOR ///

    constructor(address addressesProvider, uint8 eModeCategoryId) MorphoStorage(addressesProvider, eModeCategoryId) {}

    /// EXTERNAL ///

    function supplyLogic(address underlying, uint256 amount, address from, address onBehalf, uint256 maxLoops)
        external
        returns (uint256)
    {
        Types.Market storage market = _validateSupplyInput(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        ERC20(underlying).transferFrom2(from, address(this), amount);

        Types.SupplyRepayVars memory vars = _executeSupply(underlying, amount, onBehalf, maxLoops, indexes);

        _POOL.repayToPool(underlying, market.variableDebtToken, vars.toRepay);
        _POOL.supplyToPool(underlying, vars.toSupply);

        emit Events.Supplied(from, onBehalf, underlying, amount, vars.onPool, vars.inP2P);

        return vars.toSupply + vars.toRepay;
    }

    function supplyCollateralLogic(address underlying, uint256 amount, address from, address onBehalf)
        external
        returns (uint256)
    {
        _validateSupplyCollateralInput(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        ERC20(underlying).transferFrom2(from, address(this), amount);

        uint256 newBalance = _executeSupplyCollateral(underlying, amount, onBehalf, indexes.supply.poolIndex);

        _POOL.supplyToPool(underlying, amount);

        emit Events.CollateralSupplied(from, onBehalf, underlying, amount, newBalance);

        return amount;
    }

    function borrowLogic(address underlying, uint256 amount, address borrower, address receiver, uint256 maxLoops)
        external
        returns (uint256)
    {
        Types.Market storage market = _validateBorrowInput(underlying, amount, borrower, receiver);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);

        // The following check requires storage indexes to be up-to-date.
        _validateBorrow(underlying, amount, borrower);

        Types.BorrowWithdrawVars memory vars = _executeBorrow(underlying, amount, borrower, maxLoops, indexes);

        _POOL.withdrawFromPool(underlying, market.aToken, vars.toWithdraw);
        _POOL.borrowFromPool(underlying, vars.toBorrow);

        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Borrowed(borrower, underlying, amount, vars.onPool, vars.inP2P);

        return amount;
    }

    function withdrawLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256)
    {
        Types.Market storage market = _validateWithdrawInput(underlying, amount, supplier, receiver);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserSupplyBalanceFromIndexes(underlying, supplier, indexes.supply), amount);

        if (amount == 0) return 0;

        Types.BorrowWithdrawVars memory vars =
            _executeWithdraw(underlying, amount, supplier, _defaultMaxLoops.withdraw, indexes);

        _POOL.withdrawFromPool(underlying, market.aToken, vars.toWithdraw);
        _POOL.borrowFromPool(underlying, vars.toBorrow);

        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Withdrawn(supplier, receiver, underlying, amount, vars.onPool, vars.inP2P);

        return amount;
    }

    function withdrawCollateralLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256)
    {
        Types.Market storage market = _validateWithdrawCollateralInput(underlying, amount, supplier, receiver);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        uint256 poolSupplyIndex = indexes.supply.poolIndex;
        amount = Math.min(_getUserCollateralBalanceFromIndex(underlying, supplier, poolSupplyIndex), amount);

        if (amount == 0) return 0;

        // The following check requires storage indexes to be up-to-date.
        _validateWithdrawCollateral(underlying, amount, supplier);

        uint256 newBalance = _executeWithdrawCollateral(underlying, amount, supplier, poolSupplyIndex);

        _POOL.withdrawFromPool(underlying, market.aToken, amount);

        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.CollateralWithdrawn(supplier, receiver, underlying, amount, newBalance);

        return amount;
    }

    function repayLogic(address underlying, uint256 amount, address repayer, address onBehalf)
        external
        returns (uint256)
    {
        Types.Market storage market = _validateRepayInput(underlying, amount, onBehalf);

        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserBorrowBalanceFromIndexes(underlying, onBehalf, indexes.borrow), amount);

        if (amount == 0) return 0;

        ERC20(underlying).transferFrom2(repayer, address(this), amount);

        Types.SupplyRepayVars memory vars = _executeRepay(underlying, amount, onBehalf, _defaultMaxLoops.repay, indexes);

        _POOL.repayToPool(underlying, market.variableDebtToken, vars.toRepay);
        _POOL.supplyToPool(underlying, vars.toSupply);

        emit Events.Repaid(repayer, onBehalf, underlying, amount, vars.onPool, vars.inP2P);

        return amount;
    }

    function liquidateLogic(
        address underlyingBorrowed,
        address underlyingCollateral,
        uint256 amount,
        address borrower,
        address liquidator
    ) external returns (uint256, uint256) {
        Types.Indexes256 memory borrowIndexes = _updateIndexes(underlyingBorrowed);
        Types.Indexes256 memory collateralIndexes = _updateIndexes(underlyingCollateral);

        uint256 closeFactor = _validateLiquidate(underlyingBorrowed, underlyingCollateral, borrower);

        amount = Math.min(
            _getUserBorrowBalanceFromIndexes(underlyingBorrowed, borrower, borrowIndexes.borrow).percentMul(closeFactor), // Max liquidatable debt.
            amount
        );

        uint256 seized;
        uint256 collateralSupplyIndex = collateralIndexes.supply.poolIndex;
        (amount, seized) =
            _calculateAmountToSeize(underlyingBorrowed, underlyingCollateral, amount, borrower, collateralSupplyIndex);

        ERC20(underlyingBorrowed).transferFrom2(liquidator, address(this), amount);

        Types.SupplyRepayVars memory repayVars = _executeRepay(underlyingBorrowed, amount, borrower, 0, borrowIndexes);
        _executeWithdrawCollateral(underlyingCollateral, seized, borrower, collateralSupplyIndex);

        _POOL.repayToPool(underlyingBorrowed, _market[underlyingBorrowed].variableDebtToken, repayVars.toRepay);
        _POOL.supplyToPool(underlyingBorrowed, repayVars.toSupply);
        _POOL.withdrawFromPool(underlyingCollateral, _market[underlyingCollateral].aToken, seized);

        ERC20(underlyingCollateral).safeTransfer(liquidator, seized);

        emit Events.Liquidated(liquidator, borrower, underlyingBorrowed, amount, underlyingCollateral, seized);

        return (amount, seized);
    }
}
