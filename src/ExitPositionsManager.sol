// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "./interfaces/aave/IPool.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {PoolLib} from "./libraries/PoolLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";

contract ExitPositionsManager is PositionsManagerInternal {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;
    using PoolLib for IPool;
    using PercentageMath for uint256;
    using MarketBalanceLib for Types.MarketBalances;

    function withdrawLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserSupplyBalanceFromIndexes(underlying, supplier, indexes.supply), amount);
        _validateWithdraw(underlying, amount, receiver);

        (uint256 onPool, uint256 inP2P, uint256 toWithdraw, uint256 toBorrow) =
            _executeWithdraw(underlying, amount, supplier, _defaultMaxLoops.withdraw, indexes);

        if (toWithdraw > 0) _pool.withdrawFromPool(underlying, _market[underlying].aToken, toWithdraw);
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Withdrawn(supplier, receiver, underlying, amount, onPool, inP2P);
        return amount;
    }

    function withdrawCollateralLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(
            _marketBalances[underlying].scaledCollateralBalance(supplier).rayMul(indexes.supply.poolIndex), amount
        );
        _validateWithdrawCollateral(underlying, amount, supplier, receiver);

        _marketBalances[underlying].collateral[supplier] -= amount.rayDiv(indexes.supply.poolIndex);

        _pool.withdrawFromPool(underlying, _market[underlying].aToken, amount);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.CollateralWithdrawn(
            supplier, receiver, underlying, amount, _marketBalances[underlying].collateral[supplier]
            );
        return amount;
    }

    function repayLogic(address underlying, uint256 amount, address repayer, address onBehalf)
        external
        returns (uint256 repaid)
    {
        Types.Indexes256 memory indexes = _updateIndexes(underlying);
        amount = Math.min(_getUserBorrowBalanceFromIndexes(underlying, onBehalf, indexes.borrow), amount);
        _validateRepay(underlying, amount, onBehalf);

        ERC20(underlying).safeTransferFrom(repayer, address(this), amount);

        (uint256 onPool, uint256 inP2P, uint256 toRepay, uint256 toSupply) =
            _executeRepay(underlying, amount, onBehalf, _defaultMaxLoops.repay, indexes);

        if (toRepay > 0) _pool.repayToPool(underlying, _market[underlying].variableDebtToken, toRepay);
        if (toSupply > 0) _pool.supplyToPool(underlying, toSupply);

        emit Events.Repaid(repayer, onBehalf, underlying, amount, onPool, inP2P);
        return amount;
    }

    struct LiquidateVars {
        uint256 closeFactor;
        uint256 amountToLiquidate;
        uint256 amountToSeize;
        uint256 toSupply;
        uint256 toRepay;
        uint256 toBorrow;
        uint256 toWithdraw;
    }

    function liquidateLogic(
        address underlyingBorrowed,
        address underlyingCollateral,
        uint256 amount,
        address borrower,
        address liquidator
    ) external returns (uint256 liquidated, uint256 seized) {
        LiquidateVars memory vars;

        Types.Indexes256 memory borrowIndexes = _updateIndexes(underlyingBorrowed);
        Types.Indexes256 memory collateralIndexes = _updateIndexes(underlyingCollateral);

        vars.closeFactor = _validateLiquidate(underlyingBorrowed, underlyingCollateral, borrower);

        vars.amountToLiquidate = Math.min(
            amount,
            _getUserBorrowBalanceFromIndexes(underlyingBorrowed, borrower, borrowIndexes.borrow).percentMul(
                vars.closeFactor
            ) // Max liquidatable debt.
        );

        (vars.amountToLiquidate, vars.amountToSeize) = _calculateAmountToSeize(
            underlyingBorrowed, underlyingCollateral, vars.amountToLiquidate, borrower, collateralIndexes.supply
        );

        ERC20(underlyingBorrowed).safeTransferFrom(liquidator, address(this), vars.amountToLiquidate);

        (,, vars.toRepay, vars.toSupply) =
            _executeRepay(underlyingBorrowed, vars.amountToLiquidate, borrower, 0, borrowIndexes);
        (,, vars.toWithdraw, vars.toBorrow) =
            _executeWithdraw(underlyingCollateral, vars.amountToSeize, borrower, 0, collateralIndexes);

        _pool.repayToPool(underlyingBorrowed, _market[underlyingBorrowed].variableDebtToken, vars.toRepay);
        _pool.supplyToPool(underlyingBorrowed, vars.toSupply);
        _pool.withdrawFromPool(underlyingCollateral, _market[underlyingCollateral].aToken, vars.toWithdraw);
        _pool.borrowFromPool(underlyingCollateral, vars.toBorrow);

        ERC20(underlyingCollateral).safeTransfer(liquidator, vars.amountToSeize);

        emit Events.Liquidated(
            liquidator, borrower, underlyingBorrowed, vars.amountToLiquidate, underlyingCollateral, vars.amountToSeize
            );
        return (vars.amountToLiquidate, vars.amountToSeize);
    }
}
