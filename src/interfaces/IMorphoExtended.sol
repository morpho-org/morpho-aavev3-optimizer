// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import "./IMorpho.sol";

interface IMorphoExtended is IMorpho {
    function _collateralData(address underlying, Types.LiquidityVars memory vars)
        external
        view
        returns (uint256 collateral, uint256 borrowable, uint256 maxDebt);
    function _debt(address underlying, Types.LiquidityVars memory vars) external view returns (uint256 debtValue);
    function _assetLiquidityData(address underlying, Types.LiquidityVars memory vars)
        external
        view
        returns (uint256 underlyingPrice, uint256 ltv, uint256 liquidationThreshold, uint256 tokenUnit);
}
