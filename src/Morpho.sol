// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC1155} from "./interfaces/IERC1155.sol";

import {MarketLib} from "./libraries/MarketLib.sol";
import {MarketBalanceLib} from "./libraries/MarketBalanceLib.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

import {DelegateCall} from "@morpho-utils/DelegateCall.sol";

import {MorphoGetters} from "./MorphoGetters.sol";
import {MorphoSetters} from "./MorphoSetters.sol";
import {EntryPositionsManager} from "./EntryPositionsManager.sol";
import {ExitPositionsManager} from "./ExitPositionsManager.sol";

// @note: To add: IERC1155, Ownable
contract Morpho is MorphoGetters, MorphoSetters {
    using MarketBalanceLib for Types.MarketBalances;
    using MarketLib for Types.Market;
    using DelegateCall for address;

    /// EXTERNAL ///

    function supply(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied)
    {
        bytes memory returnData = _entryPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                EntryPositionsManager.supplyLogic.selector, underlying, amount, msg.sender, onBehalf, maxLoops
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function supplyCollateral(address underlying, uint256 amount, address onBehalf)
        external
        returns (uint256 supplied)
    {
        bytes memory returnData = _entryPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                EntryPositionsManager.supplyCollateralLogic.selector, underlying, amount, msg.sender, onBehalf
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function borrow(address underlying, uint256 amount, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed)
    {
        bytes memory returnData = _entryPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                EntryPositionsManager.borrowLogic.selector, underlying, amount, msg.sender, receiver, maxLoops
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function repay(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 repaid)
    {
        bytes memory returnData = _exitPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                ExitPositionsManager.repayLogic.selector, underlying, amount, msg.sender, onBehalf, maxLoops
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function withdraw(address underlying, uint256 amount, address to, uint256 maxLoops)
        external
        returns (uint256 withdrawn)
    {
        bytes memory returnData = _exitPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                ExitPositionsManager.withdrawLogic.selector, underlying, amount, msg.sender, to, maxLoops
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function withdrawCollateral(address underlying, uint256 amount, address to) external returns (uint256 withdrawn) {
        bytes memory returnData = _exitPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                ExitPositionsManager.withdrawCollateralLogic.selector, underlying, amount, msg.sender, to
            )
        );
        return (abi.decode(returnData, (uint256)));
    }

    function liquidate(address underlyingBorrowed, address underlyingCollateral, address user, uint256 amount)
        external
        returns (uint256 repaid, uint256 seized)
    {
        bytes memory returnData = _exitPositionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                ExitPositionsManager.liquidateLogic.selector,
                underlyingBorrowed,
                underlyingCollateral,
                amount,
                user,
                msg.sender
            )
        );
        return (abi.decode(returnData, (uint256, uint256)));
    }

    function execute(Types.ForwardRequest calldata req, bytes calldata signature)
        external
        payable
        returns (bool, bytes memory)
    {
        require(req.to == address(this), "Morpho: Can only forward to Morpho");
        require(_verify(req, signature), "Morpho: bad signature");
        _nonces[req.from] = req.nonce + 1;

        (bool success, bytes memory returndata) =
            req.to.call{gas: req.gas, value: req.value}(abi.encodePacked(req.data, req.from));

        // Validate that the relayer has sent enough gas for the call.
        // See https://ronan.eth.limo/blog/ethereum-gas-dangers/
        if (gasleft() <= req.gas / 63) {
            // We explicitly trigger invalid opcode to consume all gas and bubble-up the effects, since
            // neither revert or assert consume all gas since Solidity 0.8.0
            // https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }

        return (success, returndata);
    }
}
