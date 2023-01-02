// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IERC1155} from "./interfaces/IERC1155.sol";
import {MorphoInternal} from "./MorphoInternal.sol";
import {Types} from "./libraries/Types.sol";

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

abstract contract Morpho1155 is IERC1155, MorphoInternal {
    /// @inheritdoc IERC1155
    function setApprovalForAll(address _operator, bool _approved) external {
        for (uint256 i; i < _marketsCreated.length; ++i) {
            _isApprovedForBy[_marketsCreated[i]][msg.sender][_operator] = _approved;
        }
    }

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

    /// @inheritdoc IERC1155
    function balanceOf(address _owner, uint256 _id) public view returns (uint256) {
        (address underlying, Types.PositionType positionType) = _decodeId(_id);

        return _balanceOf(_owner, underlying, positionType);
    }

    /// @inheritdoc IERC1155
    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids)
        external
        view
        returns (uint256[] memory batchBalances)
    {
        if (_owners.length != _ids.length) revert Errors.LengthMismatch();

        batchBalances = new uint256[](_owners.length);

        for (uint256 i; i < _owners.length; ++i) {
            batchBalances[i] = balanceOf(_owners[i], _ids[i]);
        }
    }

    /// @inheritdoc IERC1155
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        uint256 nbMarkets = _marketsCreated.length;

        for (uint256 i; i < nbMarkets; ++i) {
            if (!_isApprovedForBy[_marketsCreated[i]][_owner][_operator]) return false;
        }

        return true;
    }

    function decodeId(uint256 id) external view returns (address, Types.PositionType) {
        return _decodeId(id);
    }
}
