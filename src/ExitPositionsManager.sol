// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types, Events, Errors, MarketLib, Math, PoolInteractions} from "./libraries/Libraries.sol";
import {IPool} from "./interfaces/Interfaces.sol";

import {PositionsManagerInternal} from "./PositionsManagerInternal.sol";
import {ERC20, SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

contract ExitPositionsManager is PositionsManagerInternal {
    using SafeTransferLib for ERC20;
    using PoolInteractions for IPool;

    function withdrawLogic(address poolToken, address supplier, address receiver, uint256 amount, uint256 maxLoops)
        external
    {
        Types.IndexesMem memory indexes = _updateIndexes(poolToken);
        amount = Math.min(_getUserSupplyBalance(poolToken, supplier), amount);
        _validateWithdraw(poolToken, supplier, receiver, amount);

        (uint256 onPool, uint256 inP2P, uint256 toBorrow, uint256 toWithdraw) =
            _executeWithdraw(poolToken, supplier, amount, indexes, maxLoops);

        address underlying = _market[poolToken].underlying;
        if (toWithdraw > 0) {
            _pool.withdrawFromPool(underlying, poolToken, toWithdraw);
        }
        if (toBorrow > 0) _pool.borrowFromPool(underlying, toBorrow);
        ERC20(underlying).safeTransfer(receiver, amount);

        emit Events.Withdrawn(supplier, receiver, poolToken, amount, onPool, inP2P);
    }

    function repayLogic(address poolToken, address repayer, address onBehalf, uint256 amount, uint256 maxLoops)
        external
    {
        Types.Market storage market = _market[poolToken];
        Types.IndexesMem memory indexes = _updateIndexes(poolToken);
        amount = Math.min(_getUserBorrowBalance(poolToken, onBehalf), amount);
        _validateRepay(poolToken, amount);

        ERC20 underlyingToken = ERC20(market.underlying);
        underlyingToken.safeTransferFrom(repayer, address(this), amount);

        (uint256 onPool, uint256 inP2P, uint256 toRepay, uint256 toSupply) =
            _executeRepay(poolToken, onBehalf, amount, indexes, maxLoops);

        if (toRepay > 0) _pool.repayToPool(market.underlying, toRepay);
        if (toSupply > 0) _pool.supplyToPool(market.underlying, toSupply);

        emit Events.Repaid(repayer, onBehalf, poolToken, amount, onPool, inP2P);
    }

    //   /// @notice Liquidates a position.
    //   /// @param _poolTokenBorrowed The address of the pool token the liquidator wants to repay.
    //   /// @param _poolTokenCollateral The address of the collateral pool token the liquidator wants to seize.
    //   /// @param _borrower The address of the borrower to liquidate.
    //   /// @param _amount The amount of token (in underlying) to repay.
    //   function liquidateLogic(
    //     address _poolTokenBorrowed,
    //     address _poolTokenCollateral,
    //     address _borrower,
    //     uint256 _amount
    //   ) external {
    //     Types.Market memory collateralMarket = market[_poolTokenCollateral];
    //     if (!collateralMarket.isCreatedMemory()) revert MarketNotCreated();
    //     if (collateralMarket.isLiquidateCollateralPaused) {
    //       revert LiquidateCollateralIsPaused();
    //     }
    //     Types.Market memory borrowedMarket = market[_poolTokenBorrowed];
    //     if (!borrowedMarket.isCreatedMemory()) revert MarketNotCreated();
    //     if (borrowedMarket.isLiquidateBorrowPaused) {
    //       revert LiquidateBorrowIsPaused();
    //     }

    //     if (
    //       !_isBorrowingAndSupplying(
    //         userMarkets[_borrower],
    //         borrowMask[_poolTokenBorrowed],
    //         borrowMask[_poolTokenCollateral]
    //       )
    //     ) revert UserNotMemberOfMarket();

    //     _updateIndexes(_poolTokenBorrowed);
    //     _updateIndexes(_poolTokenCollateral);

    //     Types.LiquidateVars memory vars;
    //     (vars.liquidationAllowed, vars.closeFactor) = _liquidationAllowed(
    //       _borrower,
    //       borrowedMarket.isDeprecated
    //     );
    //     if (!vars.liquidationAllowed) revert UnauthorisedLiquidate();

    //     vars.amountToLiquidate = Math.min(
    //       _amount,
    //       _getUserBorrowBalanceInOf(_poolTokenBorrowed, _borrower).percentMul(
    //         vars.closeFactor
    //       ) // Max liquidatable debt.
    //     );

    //     IPool poolMem = pool;
    //     (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = poolMem
    //       .getConfiguration(collateralMarket.underlyingToken)
    //       .getParams();
    //     (, , , vars.borrowedReserveDecimals, , ) = poolMem
    //       .getConfiguration(borrowedMarket.underlyingToken)
    //       .getParams();

    //     unchecked {
    //       vars.collateralTokenUnit = 10 ** vars.collateralReserveDecimals;
    //       vars.borrowedTokenUnit = 10 ** vars.borrowedReserveDecimals;
    //     }

    //     IPriceOracleGetter oracle = IPriceOracleGetter(
    //       addressesProvider.getPriceOracle()
    //     );
    //     vars.borrowedTokenPrice = oracle.getAssetPrice(
    //       borrowedMarket.underlyingToken
    //     );
    //     vars.collateralPrice = oracle.getAssetPrice(
    //       collateralMarket.underlyingToken
    //     );
    //     vars.amountToSeize = ((vars.amountToLiquidate *
    //       vars.borrowedTokenPrice *
    //       vars.collateralTokenUnit) /
    //       (vars.borrowedTokenUnit * vars.collateralPrice)).percentMul(
    //         vars.liquidationBonus
    //       );

    //     vars.collateralBalance = _getUserSupplyBalanceInOf(
    //       _poolTokenCollateral,
    //       _borrower
    //     );

    //     if (vars.amountToSeize > vars.collateralBalance) {
    //       vars.amountToSeize = vars.collateralBalance;
    //       vars.amountToLiquidate = ((vars.collateralBalance *
    //         vars.collateralPrice *
    //         vars.borrowedTokenUnit) /
    //         (vars.borrowedTokenPrice * vars.collateralTokenUnit)).percentDiv(
    //           vars.liquidationBonus
    //         );
    //     }

    //     _unsafeRepayLogic(
    //       _poolTokenBorrowed,
    //       msg.sender,
    //       _borrower,
    //       vars.amountToLiquidate,
    //       0
    //     );
    //     _unsafeWithdrawLogic(
    //       _poolTokenCollateral,
    //       vars.amountToSeize,
    //       _borrower,
    //       msg.sender,
    //       0
    //     );
    //     ERC20(market.underlying).safeTransfer(receiver, toWithdraw);

    //     emit Liquidated(
    //       msg.sender,
    //       _borrower,
    //       _poolTokenBorrowed,
    //       vars.amountToLiquidate,
    //       _poolTokenCollateral,
    //       vars.amountToSeize
    //     );
    //   }
}
