// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IWETH} from "src/interfaces/IWETH.sol";
import {IWSTETH} from "src/interfaces/IWSTETH.sol";
import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IBulkerGateway} from "src/interfaces/IBulkerGateway.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";

import {Types} from "src/libraries/Types.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20 as ERC20Permit2, Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";

/// @title BulkerGateway.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
contract BulkerGateway is IBulkerGateway {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;
    using Permit2Lib for ERC20Permit2;

    /* ERRORS */

    /// @notice Thrown when another address than WETH sends ETH to the contract.
    error OnlyWETH();

    /// @notice Thrown when the `morpho` address passed in the constructor is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount used is zero.
    error AmountIsZero();

    /* CONSTANTS */

    /// @dev The address of the WETH contract.
    address internal constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev The address of the stETH contract.
    address internal constant _ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @dev The address of the wstETH contract.
    address internal constant _WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev The address of the Uniswap V3 router.
    address internal constant _ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /// @dev The address of the Morpho DAO.
    address internal constant _MORPHO_DAO = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;

    /* IMMUTABLES */

    IMorpho internal immutable _MORPHO;

    /* CONSTRUCTOR */

    constructor(address morpho) {
        if (morpho == address(0)) revert AddressIsZero();

        _MORPHO = IMorpho(morpho);

        ERC20(_WETH).safeApprove(morpho, type(uint256).max);
        ERC20(_ST_ETH).safeApprove(_WST_ETH, type(uint256).max);
        ERC20(_WST_ETH).safeApprove(morpho, type(uint256).max);
    }

    /* EXTERNAL */

    /// @notice Returns the address of the WETH contract.
    function WETH() external pure returns (address) {
        return _WETH;
    }

    /// @notice Returns the address of the stETH contract.
    function stETH() external pure returns (address) {
        return _ST_ETH;
    }

    /// @notice Returns the address of the wstETH contract.
    function wstETH() external pure returns (address) {
        return _WST_ETH;
    }

    /// @notice Returns the address of the Uniswap V3 router.
    function ROUTER() external pure returns (address) {
        return _ROUTER;
    }

    /// @notice Returns the address of the Morpho protocol.
    function MORPHO() external view returns (address) {
        return address(_MORPHO);
    }

    /// @notice Returns the address of the Morpho DAO.
    function MORPHO_DAO() external pure returns (address) {
        return _MORPHO_DAO;
    }

    /// @notice Transfers this contract's given ERC20 balance to the Morpho DAO, to avoid having funds stuck.
    function skim(address asset) external {
        ERC20(asset).safeTransfer(_MORPHO_DAO, ERC20(asset).balanceOf(address(this)));
    }

    /// @notice Executes the given batch of actions, with the given input data.
    /// @dev This function is expected to be delegate-called by the user contract, in order to act on their behalf.
    /// @param actions The batch of action to execute, one after the other.
    /// @param data The array of data corresponding to each input action.
    function execute(ActionType[] calldata actions, bytes[] calldata data) external payable {
        uint256 nbActions = actions.length;
        if (nbActions != data.length) {
            revert InconsistentParameters(nbActions, data.length);
        }

        uint256 outputAmount;
        uint256 lastOutputAmount;
        for (uint256 i; i < nbActions; ++i) {
            outputAmount = _performAction(actions[i], data[i], lastOutputAmount);

            if (outputAmount != type(uint256).max) lastOutputAmount = outputAmount;
        }
    }

    /// @dev Only the WETH contract is allowed to transfer ETH to this contracts.
    receive() external payable {
        if (msg.sender != _WETH) revert OnlyWETH();
    }

    /* INTERNAL */

    /// @notice Performs the given action, given its associated parameters.
    /// @param action The type of action to perform on behalf of the caller.
    /// @param data The data to decode, associated with the action.
    /// @param lastOutputAmount The output amount of the last executed action.
    /// @return The output amount of the executed action.
    function _performAction(ActionType action, bytes memory data, uint256 lastOutputAmount)
        internal
        returns (uint256)
    {
        if (action == ActionType.APPROVE2) {
            (address asset, uint256 amount, uint256 deadline, Types.Signature memory signature, OpType opType) =
                abi.decode(data, (address, uint256, uint256, Types.Signature, OpType));

            return _approve2(asset, _computeAmount(amount, lastOutputAmount, opType), deadline, signature);
        } else if (action == ActionType.TRANSFER_FROM2) {
            (address asset, uint256 amount, OpType opType) = abi.decode(data, (address, uint256, OpType));

            return _transferFrom2(asset, _computeAmount(amount, lastOutputAmount, opType));
        } else if (action == ActionType.APPROVE_MANAGER) {
            (bool isAllowed, uint256 nonce, uint256 deadline, Types.Signature memory signature) =
                abi.decode(data, (bool, uint256, uint256, Types.Signature));

            return _approveManager(isAllowed, nonce, deadline, signature);
        } else if (action == ActionType.SUPPLY) {
            (address asset, uint256 amount, address onBehalf, uint256 maxIterations, OpType opType) =
                abi.decode(data, (address, uint256, address, uint256, OpType));

            return _supply(asset, _computeAmount(amount, lastOutputAmount, opType), onBehalf, maxIterations);
        } else if (action == ActionType.SUPPLY_COLLATERAL) {
            (address asset, uint256 amount, address onBehalf, OpType opType) =
                abi.decode(data, (address, uint256, address, OpType));

            return _supplyCollateral(asset, _computeAmount(amount, lastOutputAmount, opType), onBehalf);
        } else if (action == ActionType.BORROW) {
            (address asset, uint256 amount, address receiver, uint256 maxIterations, OpType opType) =
                abi.decode(data, (address, uint256, address, uint256, OpType));

            return _borrow(asset, _computeAmount(amount, lastOutputAmount, opType), receiver, maxIterations);
        } else if (action == ActionType.REPAY) {
            (address asset, uint256 amount, address onBehalf, OpType opType) =
                abi.decode(data, (address, uint256, address, OpType));

            return _repay(asset, _computeAmount(amount, lastOutputAmount, opType), onBehalf);
        } else if (action == ActionType.WITHDRAW) {
            (address asset, uint256 amount, address receiver, uint256 maxIterations, OpType opType) =
                abi.decode(data, (address, uint256, address, uint256, OpType));

            return _withdraw(asset, _computeAmount(amount, lastOutputAmount, opType), receiver, maxIterations);
        } else if (action == ActionType.WITHDRAW_COLLATERAL) {
            (address asset, uint256 amount, address receiver, OpType opType) =
                abi.decode(data, (address, uint256, address, OpType));

            return _withdrawCollateral(asset, _computeAmount(amount, lastOutputAmount, opType), receiver);
        } else if (action == ActionType.CLAIM_REWARDS) {
            (address[] memory assets, address onBehalf) = abi.decode(data, (address[], address));

            return _claimRewards(assets, onBehalf);
        } else if (action == ActionType.SWAP_EXACT_IN) {
            (uint256 amountIn, uint256 maxPrice, bytes memory path, OpType opType) =
                abi.decode(data, (uint256, uint256, bytes, OpType));

            return _swapExactIn(_computeAmount(amountIn, lastOutputAmount, opType), maxPrice, path);
        } else if (action == ActionType.SWAP_EXACT_OUT) {
            (uint256 amountOut, uint256 maxPrice, bytes memory path, OpType opType) =
                abi.decode(data, (uint256, uint256, bytes, OpType));

            return _swapExactOut(_computeAmount(amountOut, lastOutputAmount, opType), maxPrice, path);
        } else if (action == ActionType.WRAP_ETH) {
            (uint256 amount, OpType opType) = abi.decode(data, (uint256, OpType));

            return _wrapEth(_computeAmount(amount, lastOutputAmount, opType));
        } else if (action == ActionType.UNWRAP_ETH) {
            (uint256 amount, address receiver, OpType opType) = abi.decode(data, (uint256, address, OpType));

            return _unwrapEth(_computeAmount(amount, lastOutputAmount, opType), receiver);
        } else if (action == ActionType.WRAP_ST_ETH) {
            (uint256 amount, OpType opType) = abi.decode(data, (uint256, OpType));

            return _wrapStEth(_computeAmount(amount, lastOutputAmount, opType));
        } else if (action == ActionType.UNWRAP_ST_ETH) {
            (uint256 amount, address receiver, OpType opType) = abi.decode(data, (uint256, address, OpType));

            return _unwrapStEth(_computeAmount(amount, lastOutputAmount, opType), receiver);
        }

        return type(uint256).max;
    }

    /// @notice Approves the given `amount` of `asset` from sender to be spent by this contract via Permit2 with the given `deadline` & EIP712 `signature`.
    /// @param asset The address of the asset to approve.
    /// @param amount The amount of `asset` to approve.
    /// @param deadline The maximum timestamp at which the given signature is valid.
    /// @param signature The Permit2 allowance message signature.
    /// @return The amount approved (in asset).
    function _approve2(address asset, uint256 amount, uint256 deadline, Types.Signature memory signature)
        internal
        returns (uint256)
    {
        ERC20Permit2(asset).simplePermit2(
            msg.sender, address(this), amount, deadline, signature.v, signature.r, signature.s
        );

        return amount;
    }

    /// @notice Transfers the given `amount` of `asset` from sender to this contract via ERC20 transfer with Permit2 fallback.
    /// @param asset The address of the asset to transfer.
    /// @param amount The amount of `asset` to transfer.
    /// @return The amount transfered (in asset).
    function _transferFrom2(address asset, uint256 amount) internal returns (uint256) {
        ERC20Permit2(asset).transferFrom2(msg.sender, address(this), amount);

        return amount;
    }

    /// @notice Approves this contract to manage the position of `msg.sender` via EIP712 `signature`.
    /// @param isAllowed Whether this contract is allowed to manage `msg.sender`'s position or not.
    /// @param nonce The nonce of the signed message.
    /// @param deadline The maximum timestamp at which the given signature is valid.
    /// @param signature The Permit2 allowance message signature.
    /// @return Always `type(uint256).max`. Is not taken into account as an action's output amount.
    function _approveManager(bool isAllowed, uint256 nonce, uint256 deadline, Types.Signature memory signature)
        internal
        returns (uint256)
    {
        _MORPHO.approveManagerWithSig(msg.sender, address(this), isAllowed, nonce, deadline, signature);

        return type(uint256).max;
    }

    /// @notice Supplies `amount` of `asset` of `onBehalf` using permit2 in a single tx.
    ///         The supplied amount cannot be used as collateral but is eligible for the peer-to-peer matching.
    /// @param asset The address of the `asset` asset to supply.
    /// @param amount The amount of `asset` to supply.
    /// @param onBehalf The address that will receive the supply position.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    /// @return The amount supplied (in asset).
    function _supply(address asset, uint256 amount, address onBehalf, uint256 maxIterations)
        internal
        returns (uint256)
    {
        if (ERC20(asset).allowance(address(this), address(_MORPHO)) != 0) {
            ERC20(asset).safeApprove(address(_MORPHO), type(uint256).max);
        }

        return _MORPHO.supply(asset, amount, onBehalf, maxIterations);
    }

    /// @notice Supplies `amount` of `asset` collateral to the pool on behalf of `onBehalf`.
    /// @param asset The address of the `asset` asset to supply.
    /// @param amount The amount of `asset` to supply.
    /// @param onBehalf The address that will receive the supply position.
    /// @return The collateral amount supplied (in asset).
    function _supplyCollateral(address asset, uint256 amount, address onBehalf) internal returns (uint256) {
        if (ERC20(asset).allowance(address(this), address(_MORPHO)) != 0) {
            ERC20(asset).safeApprove(address(_MORPHO), type(uint256).max);
        }

        return _MORPHO.supplyCollateral(asset, amount, onBehalf);
    }

    /// @notice Borrows `amount` of `asset` on behalf of the sender. Sender must have previously approved the bulker as their manager on Morpho.
    /// @param asset The address of the asset asset to borrow.
    /// @param amount The amount of `asset` to borrow.
    /// @param receiver The address that will receive the borrowed funds.
    /// @param maxIterations The maximum number of iterations allowed during the matching process. Using 4 was shown to be efficient in Morpho Labs' simulations.
    /// @return The amount borrowed (in asset).
    function _borrow(address asset, uint256 amount, address receiver, uint256 maxIterations)
        internal
        returns (uint256)
    {
        return _MORPHO.borrow(asset, amount, msg.sender, receiver, maxIterations);
    }

    /// @notice Repays `amount` of `asset` on behalf of `onBehalf`.
    /// @param asset The address of the asset asset to borrow.
    /// @param amount The amount of `asset` to repay.
    /// @param onBehalf The address whose position will be repaid.
    /// @return The amount repaid (in asset).
    function _repay(address asset, uint256 amount, address onBehalf) internal returns (uint256) {
        if (ERC20(asset).allowance(address(this), address(_MORPHO)) != 0) {
            ERC20(asset).safeApprove(address(_MORPHO), type(uint256).max);
        }

        return _MORPHO.repay(asset, amount, onBehalf);
    }

    /// @notice Withdraws `amount` of `asset` on behalf of `onBehalf`. Sender must have previously approved the bulker as their manager on Morpho.
    /// @param asset The address of the asset asset to withdraw.
    /// @param amount The amount of `asset` to withdraw.
    /// @param receiver The address that will receive the withdrawn funds.
    /// @param maxIterations The maximum number of iterations allowed during the matching process.
    ///                      If it is less than `Morpho.defaultIterations.withdraw`, the latter will be used.
    ///                      Pass 0 to fallback to the `Morpho.defaultIterations.withdraw`.
    /// @return The amount withdrawn.
    function _withdraw(address asset, uint256 amount, address receiver, uint256 maxIterations)
        internal
        returns (uint256)
    {
        return _MORPHO.withdraw(asset, amount, msg.sender, receiver, maxIterations);
    }

    /// @notice Withdraws `amount` of `asset` on behalf of sender. Sender must have previously approved the bulker as their manager on Morpho.
    /// @param asset The address of the asset asset to withdraw.
    /// @param amount The amount of `asset` to withdraw.
    /// @param receiver The address that will receive the withdrawn funds.
    /// @return The collateral amount withdrawn (in asset).
    function _withdrawCollateral(address asset, uint256 amount, address receiver) internal returns (uint256) {
        return _MORPHO.withdrawCollateral(asset, amount, msg.sender, receiver);
    }

    /// @notice Claims rewards for the given assets, on behalf of an address, sending the funds to the given address.
    /// @param assets The addresses of the markets.
    /// @param onBehalf The address of which to claim the rewards.
    /// @return Always `type(uint256).max`. Is not taken into account as an action's output amount.
    function _claimRewards(address[] memory assets, address onBehalf) internal returns (uint256) {
        _MORPHO.claimRewards(assets, onBehalf);

        return type(uint256).max;
    }

    /// @notice Swaps the exact input amount along the Uniswap V3 path, expecting a minimum output amount based on the given price and a maximum slippage.
    /// @param amountIn The exact input amount to swap (will be capped to the caller's balance).
    /// @param maxPrice The maximum amount of input tokens to get a unit of output token (with `18 + tokenInDecimals - tokenOutDecimals` decimals).
    /// @param path The Uniswap V3 swap path.
    /// @return The amount of output token swapped.
    function _swapExactIn(uint256 amountIn, uint256 maxPrice, bytes memory path) internal returns (uint256) {
        return ISwapRouter(_ROUTER).exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountIn.wadDiv(maxPrice)
            })
        );
    }

    /// @notice Swaps the exact output amount along the Uniswap V3 path, expecting a maximum input amount based on the given price and a maximum slippage.
    /// @param amountOut The exact output amount to swap.
    /// @param maxPrice The maximum amount of input tokens to get a unit of output token (with `18 + tokenInDecimals - tokenOutDecimals` decimals).
    /// @param path The Uniswap V3 swap path (reversed compared to _swapExactIn).
    /// @return The amount of input token swapped.
    function _swapExactOut(uint256 amountOut, uint256 maxPrice, bytes memory path) internal returns (uint256) {
        return ISwapRouter(_ROUTER).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountOut.wadMul(maxPrice)
            })
        );
    }

    /// @notice Wraps the given input of ETH to WETH.
    /// @param amount The amount of ETH to wrap.
    /// @return The amount WETH corresponding to the input amount.
    function _wrapEth(uint256 amount) internal returns (uint256) {
        if (amount == 0) revert AmountIsZero();

        IWETH(_WETH).deposit{value: amount}();

        return amount;
    }

    /// @notice Unwraps the given input of WETH to ETH.
    /// @param amount The amount of WETH to unwrap.
    /// @param receiver The address to which to send the unwrapped ETH.
    /// @return The amount ETH corresponding to the input amount.
    function _unwrapEth(uint256 amount, address receiver) internal returns (uint256) {
        if (amount == 0) revert AmountIsZero();

        IWETH(_WETH).withdraw(amount);

        SafeTransferLib.safeTransferETH(receiver, amount);

        return amount;
    }

    /// @notice Wraps the given input of stETH to wstETH.
    /// @param amount The amount of stETH to wrap.
    /// @return The amount stETH wrapped.
    function _wrapStEth(uint256 amount) internal returns (uint256) {
        if (amount == 0) revert AmountIsZero();

        return IWSTETH(_WST_ETH).wrap(amount);
    }

    /// @notice Unwraps the given input of wstETH to stETH.
    /// @param amount The amount of wstETH to unwrap.
    /// @param receiver The address to which to send the unwrapped stETH.
    /// @return unwrapped The amount of stETH unwrapped.
    function _unwrapStEth(uint256 amount, address receiver) internal returns (uint256 unwrapped) {
        if (amount == 0) revert AmountIsZero();

        unwrapped = IWSTETH(_WST_ETH).unwrap(amount);

        ERC20(_ST_ETH).safeTransfer(receiver, unwrapped);
    }

    /// @notice Returns the amount computed from the output amount of the last executed action, given a math operation and an operand.
    /// @param operand The operand to apply to the last output amount, via the given operation (should be the current action's input amount).
    /// @param lastOutputAmount The output amount of the last executed action.
    /// @param opType The math operation to apply to the last output amount and the given operand.
    /// @return amount The computed amount.
    function _computeAmount(uint256 operand, uint256 lastOutputAmount, OpType opType)
        internal
        pure
        returns (uint256 amount)
    {
        if (opType == OpType.RAW) {
            return operand;
        } else if (opType == OpType.ADD) {
            return lastOutputAmount + operand;
        } else if (opType == OpType.SUB) {
            return lastOutputAmount - operand;
        } else if (opType == OpType.MUL) {
            return lastOutputAmount.wadMul(operand);
        } else if (opType == OpType.DIV) {
            return lastOutputAmount.wadDiv(operand);
        }
    }
}
