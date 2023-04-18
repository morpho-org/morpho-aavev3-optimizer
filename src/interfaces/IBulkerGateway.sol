// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IBulkerGateway {
    /* ERRORS */

    /// @notice Thrown when an unknown address is about to be approved.
    /// @param spender The address of the unsafe spender.
    error UnsafeApproval(address spender);

    /// @notice Thrown when execution parameters don't have the same length.
    /// @param nbActions The number of input actions.
    /// @param nbData The number of data inputs.
    error InconsistentParameters(uint256 nbActions, uint256 nbData);

    /// @notice Thrown when another address than WETH sends ETH to the contract.
    error OnlyWETH();

    /// @notice Thrown when the `morpho` address passed in the constructor is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount used is zero.
    error AmountIsZero();

    /// @notice Thrown when transfer is attempted from the bulker to the bulker.
    error TransferToSelf();

    /// @notice Thrown when the action is unsupported.
    error UnsupportedAction(ActionType action);

    /* ENUMS */

    enum ActionType {
        APPROVE2,
        TRANSFER_FROM2,
        APPROVE_MANAGER,
        SUPPLY,
        SUPPLY_COLLATERAL,
        BORROW,
        REPAY,
        WITHDRAW,
        WITHDRAW_COLLATERAL,
        CLAIM_REWARDS,
        WRAP_ETH,
        UNWRAP_ETH,
        WRAP_ST_ETH,
        UNWRAP_ST_ETH,
        SKIM
    }

    /* FUNCTIONS */

    function WETH() external pure returns (address);
    function stETH() external pure returns (address);
    function wstETH() external pure returns (address);

    function MORPHO() external view returns (address);

    function execute(ActionType[] calldata actions, bytes[] calldata data) external payable;
}
