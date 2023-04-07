// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IMorphoBulker {
    /* ERRORS */

    /// @notice Thrown when an unknown address is about to be approved.
    /// @param spender The address of the unsafe spender.
    error UnsafeApproval(address spender);

    /// @notice Thrown when execution parameters don't have the same length.
    /// @param nbActions The number of input actions.
    /// @param nbData The number of data inputs.
    error InconsistentParameters(uint256 nbActions, uint256 nbData);

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
        SWAP_EXACT_IN,
        SWAP_EXACT_OUT,
        WRAP_ETH,
        UNWRAP_ETH,
        WRAP_ST_ETH,
        UNWRAP_ST_ETH
    }

    enum OpType {
        RAW,
        ADD,
        SUB,
        MUL,
        DIV
    }

    /* FUNCTIONS */

    function WETH() external pure returns (address);
    function stETH() external pure returns (address);
    function wstETH() external pure returns (address);

    function ROUTER() external view returns (address);
    function MORPHO() external view returns (address);
    function MORPHO_DAO() external pure returns (address);

    function skim(address erc20) external;

    function execute(ActionType[] calldata actions, bytes[] calldata data) external payable;
}
