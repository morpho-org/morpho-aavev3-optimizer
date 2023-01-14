// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool} from "../interfaces/aave/IPool.sol";
import {IAToken} from "../interfaces/aave/IAToken.sol";
import {IVariableDebtToken} from "../interfaces/aave/IVariableDebtToken.sol";

import {Constants} from "./Constants.sol";
import {Math} from "@morpho-utils/math/Math.sol";

library PoolLib {
    function supplyToPool(IPool pool, address underlying, uint256 amount) internal {
        if (amount == 0) return;

        pool.supply(underlying, amount, address(this), Constants.NO_REFERRAL_CODE);
    }

    function withdrawFromPool(IPool pool, address underlying, address aToken, uint256 amount) internal {
        if (amount == 0) return;

        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        amount = Math.min(IAToken(aToken).balanceOf(address(this)), amount);
        pool.withdraw(underlying, amount, address(this));
    }

    function borrowFromPool(IPool pool, address underlying, uint256 amount) internal {
        if (amount == 0) return;

        pool.borrow(underlying, amount, Constants.VARIABLE_INTEREST_MODE, Constants.NO_REFERRAL_CODE, address(this));
    }

    function repayToPool(IPool pool, address underlying, address variableDebtToken, uint256 amount) internal {
        if (amount == 0 || IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)) == 0) return;

        pool.repay(underlying, amount, Constants.VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }

    function getCurrentPoolIndexes(IPool pool, address underlying)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        poolSupplyIndex = pool.getReserveNormalizedIncome(underlying);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlying);
    }
}
