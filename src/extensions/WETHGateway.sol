// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IWETH} from "../interfaces/IWETH.sol";
import {IMorpho} from "../interfaces/IMorpho.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

/// @title WETHGateway
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice A contract allowing to wrap and unwrap ETH to interact with Morpho.
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

    /// @notice Returns the address of the WETH address.
    function WETH() external pure returns (address) {
        return _WETH;
    }

    /// @notice Returns the address of the Morpho address.
    function morpho() external view returns (address) {
        return address(_morpho);
    }

    /// @notice Wraps `msg.value` of ETH to WETH and supplies it to the Morpho on behalf of `onBehalf`.
    function supplyETH(address onBehalf, uint256 maxIterations) external payable {
        _wrapETH(msg.value);
        _morpho.supply(_WETH, msg.value, onBehalf, maxIterations);
    }

    /// @notice Wraps `msg.value` of ETH to WETH and supplies it as collateral to the Morpho on behalf of `onBehalf`.
    function supplyCollateralETH(address onBehalf) external payable {
        _wrapETH(msg.value);
        _morpho.supplyCollateral(_WETH, msg.value, onBehalf);
    }

    /// @notice Borrows WETH on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function borrowETH(uint256 amount, uint256 maxIterations) external {
        amount = _morpho.borrow(_WETH, amount, msg.sender, address(this), maxIterations);
        _unwrapAndTransferETH(amount);
    }

    /// @notice Wraps `msg.value` of ETH to WETH and repays `onBehalf`'s debt on Morpho.
    function repayETH(address onBehalf) external payable {
        _wrapETH(msg.value);
        _morpho.repay(_WETH, msg.value, onBehalf);
    }

    /// @notice Withdraws WETH up to `amount` on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function withdrawETH(uint256 amount) external {
        amount = _morpho.withdraw(_WETH, amount, msg.sender, address(this));
        _unwrapAndTransferETH(amount);
    }

    /// @notice Withdraws WETH as collateral up to `amount` on behalf of `msg.sender`, unwraps it to WETH and sends it to `msg.sender`.
    ///         Note: `msg.sender` must have approved this contract to be its manager.
    function withdrawCollateralETH(uint256 amount) external {
        amount = _morpho.withdrawCollateral(_WETH, amount, msg.sender, address(this));
        _unwrapAndTransferETH(amount);
    }

    /// @dev Only the WETH contract is allowed to transfer ETH to this contracts.
    receive() external payable {
        if (msg.sender != _WETH) revert OnlyWETH();
    }

    /// INTERNAL ///

    /// @dev Wraps `amount` of ETH to WETH.
    function _wrapETH(uint256 amount) internal {
        IWETH(_WETH).deposit{value: amount}();
    }

    /// @dev Unwraps `amount` of WETH to ETH and transfers it to `msg.sender`.
    function _unwrapAndTransferETH(uint256 amount) internal {
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }
}
