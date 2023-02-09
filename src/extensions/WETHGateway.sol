// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IWETH} from "../interfaces/IWETH.sol";
import {IMorpho} from "../interfaces/IMorpho.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

contract WETHGateway {
    using SafeTransferLib for ERC20;

    /// ERRORS ///

    error OnlyWETH();

    /// CONSTANTS ///

    address internal constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// IMMUTABLES ///

    IMorpho internal immutable _morpho;

    /// CONSTRUCTOR ///

    constructor(address morpho) {
        _morpho = IMorpho(morpho);
        ERC20(_WETH).safeApprove(morpho, type(uint256).max);
    }

    /// EXTERNAL ///

    function WETH() external pure returns (address) {
        return _WETH;
    }

    function morpho() external view returns (IMorpho) {
        return _morpho;
    }

    /// @notice Wraps `msg.value` of ETH to WETH and supplies it to the Morpho on behalf of `onBehalf`.
    function supplyETH(address onBehalf, uint256 maxIterations) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.supply(_WETH, msg.value, onBehalf, maxIterations);
    }

    /// @notice Wraps `msg.value` of ETH to WETH and supplies it as collateral to the Morpho on behalf of `onBehalf`.
    function supplyCollateralETH(address onBehalf) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.supplyCollateral(_WETH, msg.value, onBehalf);
    }

    /// @notice Borrows WETH on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function borrowETH(uint256 amount, uint256 maxIterations) external {
        amount = _morpho.borrow(_WETH, amount, msg.sender, maxIterations);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /// @notice Wraps `msg.value` of ETH to WETH and repays `onBehalf`'s debt on Morpho.
    function repayETH(address onBehalf) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.repay(_WETH, msg.value, onBehalf);
    }

    /// @notice Withdraws WETH up to `amount` on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function withdrawETH(uint256 amount) external {
        amount = _morpho.withdraw(_WETH, amount, msg.sender);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /// @notice Withdraws WETH as collateral up to `amount` on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function withdrawCollateralETH(uint256 amount) external {
        amount = _morpho.withdrawCollateral(_WETH, amount, msg.sender);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /// @dev Only the WETH contract is allowed to transfer ETH to this contracts.
    receive() external payable {
        if (msg.sender != _WETH) revert OnlyWETH();
    }
}
