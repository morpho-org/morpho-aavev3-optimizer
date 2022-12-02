// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC1155/ERC1155.sol";

contract Morpho is ERC1155 {
    /// ERRORS ///

    error SomethingWentWrong();
    error CannotTransferBorrow();

    /// ENUMS ///

    enum PositionType {
        SUPPLY,
        BORROW
    }

    /// STRUCTS ///

    struct Balance {
        uint128 onPool;
        uint128 inP2P;
    }

    /// STORAGE ///

    mapping(address => mapping(address => Balance)) public supplyScaledBalance; // underlying => user => balance
    mapping(address => mapping(address => Balance)) public borrowScaledBalance; // underlying => user => balance

    /// CONSTRUCTOR ///

    constructor() ERC1155("https://morpho.xyz/metadata/") {}

    /// EXTERNAL ///

    function supply(address _underlying, uint256 _amount, address _from, address _to)
        external
        returns (uint256 supplied)
    {
        supplied = _supply(_underlying, _amount, _from, _to);
    }

    function borrow(address _underlying, uint256 _amount, address _from, address _to)
        external
        returns (uint256 borrowed)
    {
        borrowed = _borrow(_underlying, _amount, _from, _to);
        require(_liquidityCheck(_to));
    }

    function repay(address _underlying, uint256 _amount, address _from, address _to)
        external
        returns (uint256 repaid)
    {
        repaid = _repay(_underlying, _amount, _from, _to);
    }

    function withdraw(address _underlying, uint256 _amount, address _from, address _to)
        external
        returns (uint256 withdrawn)
    {
        withdrawn = _withdraw(_underlying, _amount, _from, _to);
        require(_liquidityCheck(_from));
    }

    function liquidate(address _collateralAsset, address _borrowedAsset, uint256 _amount, address _user)
        external
        returns (uint256 repaid, uint256 seized)
    {
        require(!_liquidityCheck(_user));
        return _liquidate(_collateralAsset, _borrowedAsset, _amount, _user);
    }

    /// INTERNAL ///

    function _supply(address _underlying, uint256 _amount, address _from, address _to)
        internal
        returns (uint256 supplied)
    {
        // ...
    }

    function _borrow(address _underlying, uint256 _amount, address _from, address _to)
        internal
        returns (uint256 borrowed)
    {
        // ...
    }

    function _repay(address _underlying, uint256 _amount, address _from, address _to)
        internal
        returns (uint256 repaid)
    {
        // ...
    }

    function _withdraw(address _underlying, uint256 _amount, address _from, address _to)
        internal
        returns (uint256 withdrawn)
    {
        // ...
    }

    function _liquidate(address _collateralAsset, address _borrowedAsset, uint256 _amount, address _user)
        internal
        returns (uint256 repaid, uint256 seized)
    {
        // ...
    }

    function _liquidityCheck(address _user) internal returns (bool) {
        // ...
    }

    function _getUnderlyingAndPositionTypeFromId(uint256 _id)
        internal
        pure
        returns (address poolToken, PositionType positionType)
    {
        poolToken = address(uint160(_id));
        uint256 firstBit = _id >> 255;
        if (firstBit == 0) {
            positionType = PositionType.SUPPLY;
        } else if (firstBit == 1) {
            positionType = PositionType.BORROW;
        } else {
            revert SomethingWentWrong();
        }
    }

    /// ERC1155 ///

    function uri(uint256 _id) public pure override returns (string memory) {
        return "https://morpho.xyz/supercooluri/";
    }

    function balanceOf(address _owner, uint256 _id) public view override returns (uint256) {
        (address poolToken, PositionType positionType) = _getUnderlyingAndPositionTypeFromId(_id);
        Balance memory balance;

        if (positionType == PositionType.SUPPLY) {
            balance = supplyScaledBalance[poolToken][_owner];
        } else if (positionType == PositionType.BORROW) {
            balance = borrowScaledBalance[poolToken][_owner];
        } else {
            revert SomethingWentWrong();
        }

        return balance.onPool + balance.inP2P;
    }

    function setApprovalForAll(address _operator, bool _approved) public override {
        // ...
        super.setApprovalForAll(_operator, _approved);
    }

    function _safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data)
        internal
        override
    {
        (address poolToken, PositionType positionType) = _getUnderlyingAndPositionTypeFromId(_id);
        uint128 amount = uint128(_amount); // TODO: Safe cast

        if (positionType == PositionType.SUPPLY) {
            supplyScaledBalance[poolToken][_from].onPool -= amount;
            supplyScaledBalance[poolToken][_to].onPool += amount;
            supplyScaledBalance[poolToken][_from].inP2P -= amount;
            supplyScaledBalance[poolToken][_to].inP2P += amount;
        } else {
            // TODO: Check approval...

            if (positionType == PositionType.BORROW) {
                borrowScaledBalance[poolToken][_from].onPool -= amount;
                borrowScaledBalance[poolToken][_to].onPool += amount;
                borrowScaledBalance[poolToken][_from].inP2P -= amount;
                borrowScaledBalance[poolToken][_to].inP2P += amount;
            } else {
                revert SomethingWentWrong();
            }

            require(_liquidityCheck(_to));
        }

        // TODO: Update DS...
    }
}
