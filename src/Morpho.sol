// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "./interfaces/IMorpho.sol";
import {IERC1155} from "./interfaces/IERC1155.sol";
import {IPositionsManager} from "./interfaces/IPositionsManager.sol";

import {DelegateCall} from "@morpho-utils/DelegateCall.sol";

import {MorphoStorage} from "./MorphoStorage.sol";
import {MorphoGetters} from "./MorphoGetters.sol";
import {MorphoSetters} from "./MorphoSetters.sol";

// @note: To add: IERC1155
contract Morpho is IMorpho, MorphoGetters, MorphoSetters {
    using DelegateCall for address;

    /// CONSTRUCTOR ///

    constructor(address addressesProvider) MorphoStorage(addressesProvider) {}

    /// EXTERNAL ///

    function supply(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.supplyLogic.selector, underlying, amount, msg.sender, onBehalf, maxLoops
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function supplyCollateral(address underlying, uint256 amount, address onBehalf)
        external
        returns (uint256 supplied)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.supplyCollateralLogic.selector, underlying, amount, msg.sender, onBehalf
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function borrow(address underlying, uint256 amount, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.borrowLogic.selector, underlying, amount, msg.sender, receiver, maxLoops
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function repay(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 repaid)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.repayLogic.selector, underlying, amount, msg.sender, onBehalf, maxLoops
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function withdraw(address underlying, uint256 amount, address to, uint256 maxLoops)
        external
        returns (uint256 withdrawn)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.withdrawLogic.selector, underlying, amount, msg.sender, to, maxLoops
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function withdrawCollateral(address underlying, uint256 amount, address to) external returns (uint256 withdrawn) {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.withdrawCollateralLogic.selector, underlying, amount, msg.sender, to
            )
        );

        return (abi.decode(returnData, (uint256)));
    }

    function liquidate(address underlyingBorrowed, address underlyingCollateral, address user, uint256 amount)
        external
        returns (uint256 repaid, uint256 seized)
    {
        bytes memory returnData = _positionsManager.functionDelegateCall(
            abi.encodeWithSelector(
                IPositionsManager.liquidateLogic.selector,
                underlyingBorrowed,
                underlyingCollateral,
                amount,
                user,
                msg.sender
            )
        );

        return (abi.decode(returnData, (uint256, uint256)));
    }
}
