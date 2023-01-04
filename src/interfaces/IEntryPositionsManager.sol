// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IEntryPositionsManager {
    function supplyLogic(address underlying, uint256 amount, address from, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied);

    function supplyCollateralLogic(address underlying, uint256 amount, address from, address onBehalf)
        external
        returns (uint256 supplied);

    function borrowLogic(address underlying, uint256 amount, address borrower, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed);
}
