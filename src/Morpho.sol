// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IERC1155} from "./interfaces/IERC1155.sol";

import {MarketLib, MarketBalanceLib} from "./libraries/Libraries.sol";
import {Types} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";
import {DelegateCall} from "@morpho-utils/DelegateCall.sol";

import {MorphoGetters} from "./MorphoGetters.sol";
import {MorphoSetters} from "./MorphoSetters.sol";
import {EntryPositionsManager} from "./EntryPositionsManager.sol";
import {ExitPositionsManager} from "./ExitPositionsManager.sol";

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

    /// ERC1155 ///

    /// @inheritdoc IERC1155
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external {
        transferFrom(_from, _to, _id, _value);

        _doSafeTransferAcceptanceCheck(_from, _to, _id, _value, _data);
    }

    /// @inheritdoc IERC1155
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external {
        batchTransferFrom(_from, _to, _ids, _values);

        _doSafeBatchTransferAcceptanceCheck(_from, _to, _ids, _values, _data);
    }

    function transferFrom(address _from, address _to, uint256 _id, uint256 _value) public {
        if (_to == address(0)) revert Errors.AddressIsZero();

        _transfer(_from, _to, _id, _value);

        emit IERC1155.TransferSingle(msg.sender, _from, _to, _id, _value);
    }

    function batchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values)
        public
    {
        if (_to == address(0)) revert Errors.AddressIsZero();
        if (_values.length != _ids.length) revert Errors.LengthMismatch();

        for (uint256 i = 0; i < _ids.length; ++i) {
            uint256 id = _ids[i];
            uint256 amount = _values[i];

            _transfer(_from, _to, id, amount);
        }

        emit IERC1155.TransferBatch(msg.sender, _from, _to, _ids, _values);
    }

    /// INTERNAL ///

    function _transfer(address _from, address _to, uint256 _id, uint256 _amount) internal {
        if (_amount == 0) revert Errors.AmountIsZero();

        (address underlying, Types.PositionType positionType) = _decodeId(_id);
        if (_amount <= _balanceOf(_from, underlying, positionType)) revert Errors.InsufficientBalance();
        if (_from != msg.sender && !_isApprovedForBy[underlying][_from][msg.sender]) {
            revert Errors.UnauthorisedTransfer();
        }

        if (positionType == Types.PositionType.SUPPLY) {
            _transferSupply(underlying, _from, _to);
        } else if (positionType == Types.PositionType.COLLATERAL) {
            _transferCollateral(underlying, _from, _to);
        } else if (positionType == Types.PositionType.BORROW) {
            _transferBorrow(underlying, _from, _to);
        }
    }
}
