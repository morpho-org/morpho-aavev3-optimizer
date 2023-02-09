// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IStableDebtToken} from "@aave-v3-core/interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "@aave-v3-core/interfaces/IVariableDebtToken.sol";

import {Types} from "./Types.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {MathUtils} from "@aave-v3-core/protocol/libraries/math/MathUtils.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

/// @title ReserveDataLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library used to ease AaveV3's reserve-related calculations.
library ReserveDataLib {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function getAccruedToTreasury(DataTypes.ReserveData memory reserve, Types.Indexes256 memory indexes)
        internal
        view
        returns (uint256)
    {
        uint256 reserveFactor = reserve.configuration.getReserveFactor();
        if (reserveFactor == 0) return reserve.accruedToTreasury;

        (
            uint256 currPrincipalStableDebt,
            uint256 currTotalStableDebt,
            uint256 currAvgStableBorrowRate,
            uint40 stableDebtLastUpdateTimestamp
        ) = IStableDebtToken(reserve.stableDebtTokenAddress).getSupplyData();
        uint256 scaledTotalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply();

        uint256 currTotalVariableDebt = scaledTotalVariableDebt.rayMul(indexes.borrow.poolIndex);
        uint256 prevTotalVariableDebt = scaledTotalVariableDebt.rayMul(reserve.variableBorrowIndex);
        uint256 prevTotalStableDebt = currPrincipalStableDebt.rayMul(
            MathUtils.calculateCompoundedInterest(
                currAvgStableBorrowRate, stableDebtLastUpdateTimestamp, reserve.lastUpdateTimestamp
            )
        );

        uint256 accruedTotalDebt =
            currTotalVariableDebt + currTotalStableDebt - prevTotalVariableDebt - prevTotalStableDebt;
        if (accruedTotalDebt == 0) return reserve.accruedToTreasury;

        uint256 newAccruedToTreasury = accruedTotalDebt.percentMul(reserveFactor).rayDiv(indexes.supply.poolIndex);

        return reserve.accruedToTreasury + newAccruedToTreasury;
    }
}
