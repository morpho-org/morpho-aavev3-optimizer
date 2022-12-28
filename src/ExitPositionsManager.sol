// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPool} from "./interfaces/aave/IPool.sol";

import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {Constants} from "./libraries/Constants.sol";
import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {PoolInteractions} from "./libraries/PoolInteractions.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";

contract ExitPositionsManager is PositionsManagerInternal {
    using SafeTransferLib for ERC20;
    using PoolInteractions for IPool;
    using PercentageMath for uint256;
    using MarketBalanceLib for Types.MarketBalances;
    using WadRayMath for uint256;

    function withdrawLogic(address poolToken, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn)
    {
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);
        amount = Math.min(_getUserSupplyBalance(poolToken, supplier), amount);
        _validateWithdraw(poolToken, receiver, amount);

        (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) =
            _executeWithdraw(poolToken, supplier, amount, 0, indexes); // TODO: Replace max loops once default max is implemented

        address underlying = _market[poolToken].underlying;
        if (toWithdraw > 0) {
            _pool.withdrawFromPool(underlying, poolToken, toWithdraw);
        }
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Withdrawn(supplier, receiver, poolToken, amount, onPool, inP2P);
        return amount;
    }

    function withdrawCollateralLogic(address poolToken, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn)
    {
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);
        amount = Math.min(
            _marketBalances[poolToken].scaledCollateralBalance(supplier).rayMul(indexes.poolSupplyIndex), amount
        );
        _validateWithdrawCollateral(poolToken, supplier, receiver, amount);

        _marketBalances[poolToken].collateral[supplier] -= amount.rayDiv(indexes.poolSupplyIndex);

        address underlying = _market[poolToken].underlying;
        _pool.withdrawFromPool(underlying, poolToken, amount);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.CollateralWithdrawn(
            supplier, receiver, poolToken, amount, _marketBalances[poolToken].collateral[supplier]
            );
        return amount;
    }

    function repayLogic(address poolToken, uint256 amount, address repayer, address onBehalf)
        external
        returns (uint256 repaid)
    {
        Types.Market storage market = _market[poolToken];
        Types.Indexes256 memory indexes = _updateIndexes(poolToken);
        amount = Math.min(_getUserBorrowBalance(poolToken, onBehalf), amount);
        _validateRepay(poolToken, amount);

        ERC20 underlyingToken = ERC20(market.underlying);
        underlyingToken.safeTransferFrom(repayer, address(this), amount);

        (uint256 onPool, uint256 inP2P, uint256 toRepay, uint256 toSupply) =
            _executeRepay(poolToken, onBehalf, amount, 0, indexes); // TODO: Update max loops

        if (toRepay > 0) _pool.repayToPool(market.underlying, toRepay);
        if (toSupply > 0) _pool.supplyToPool(market.underlying, toSupply);

        emit Events.Repaid(repayer, onBehalf, poolToken, amount, onPool, inP2P);
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
        address poolTokenBorrowed,
        address poolTokenCollateral,
        uint256 amount,
        address borrower,
        address liquidator
    ) external returns (uint256 liquidated, uint256 seized) {
        LiquidateVars memory vars;

        Types.Indexes256 memory borrowIndexes = _updateIndexes(poolTokenBorrowed);
        Types.Indexes256 memory collateralIndexes = _updateIndexes(poolTokenCollateral);

        vars.closeFactor = _validateLiquidate(poolTokenBorrowed, poolTokenCollateral, borrower);

        vars.amountToLiquidate = Math.min(
            amount,
            _getUserBorrowBalance(poolTokenBorrowed, borrower).percentMul(vars.closeFactor) // Max liquidatable debt.
        );
        vars.amountToSeize;

        (vars.amountToLiquidate, vars.amountToSeize) =
            _calculateAmountToSeize(poolTokenBorrowed, poolTokenCollateral, borrower, vars.amountToLiquidate);

        ERC20(_market[poolTokenBorrowed].underlying).safeTransferFrom(liquidator, address(this), vars.amountToLiquidate);

        (,, vars.toSupply, vars.toRepay) =
            _executeRepay(poolTokenBorrowed, borrower, vars.amountToLiquidate, 0, borrowIndexes); // TODO: Update max loops
        (,, vars.toBorrow, vars.toWithdraw) =
            _executeWithdraw(poolTokenCollateral, borrower, vars.amountToSeize, 0, collateralIndexes); // TODO: Update max loops

        _pool.supplyToPool(_market[poolTokenBorrowed].underlying, vars.toSupply);
        _pool.repayToPool(_market[poolTokenBorrowed].underlying, vars.toRepay);
        _pool.borrowFromPool(_market[poolTokenCollateral].underlying, vars.toBorrow);
        _pool.withdrawFromPool(_market[poolTokenCollateral].underlying, poolTokenCollateral, vars.toWithdraw);

        ERC20(_market[poolTokenCollateral].underlying).safeTransfer(liquidator, vars.amountToSeize);

        emit Events.Liquidated(
            liquidator, borrower, poolTokenBorrowed, vars.amountToLiquidate, poolTokenCollateral, vars.amountToSeize
            );
        return (vars.amountToLiquidate, vars.amountToSeize);
    }
}
