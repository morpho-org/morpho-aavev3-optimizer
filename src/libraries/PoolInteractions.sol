// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPool} from "../interfaces/aave/IPool.sol";
import {IVariableDebtToken} from "../interfaces/aave/IVariableDebtToken.sol";
import {IAToken} from "../interfaces/aave/IAToken.sol";
import {Constants} from "./Constants.sol";
import {Math} from "morpho-utils/math/Math.sol";

library PoolInteractions {
    function supplyToPool(IPool pool, address underlying, uint256 amount) internal {
        pool.supply(underlying, amount, address(this), Constants.NO_REFERRAL_CODE);
    }

    function withdrawFromPool(IPool pool, address underlying, address poolToken, uint256 amount) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        amount = Math.min(IAToken(poolToken).balanceOf(address(this)), amount);
        pool.withdraw(underlying, amount, address(this));
    }

    function borrowFromPool(IPool pool, address underlying, uint256 amount) internal {
        pool.borrow(underlying, amount, Constants.VARIABLE_INTEREST_MODE, Constants.NO_REFERRAL_CODE, address(this));
    }

    function repayToPool(IPool pool, address underlying, uint256 amount) internal {
        if (
            amount == 0
                || IVariableDebtToken(pool.getReserveData(underlying).variableDebtTokenAddress).scaledBalanceOf(
                    address(this)
                ) == 0
        ) return;

        pool.repay(underlying, amount, Constants.VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }
}
