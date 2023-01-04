// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IExitPositionsManager {
    function repayLogic(address underlying, uint256 amount, address repayer, address onBehalf)
        external
        returns (uint256 repaid);

    function withdrawLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn);
    function withdrawCollateralLogic(address underlying, uint256 amount, address supplier, address receiver)
        external
        returns (uint256 withdrawn);

    function liquidateLogic(
        address underlyingBorrowed,
        address underlyingCollateral,
        uint256 amount,
        address borrower,
        address liquidator
    ) external returns (uint256 liquidated, uint256 seized);
}
