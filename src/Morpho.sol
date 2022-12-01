// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC1155/ERC1155.sol";

contract Morpho is ERC1155 {
    /// ERRORS ///

    error SomethingWentWrong();
    error CannotTransferBorrow();

    /// ENUMS ///

    enum TokenType {
        SUPPLY_POOL,
        SUPPLY_P2P,
        BORROW_POOL,
        BORROW_P2P
    }

    /// STRUCTS ///

    struct Balance {
        uint128 onPool;
        uint128 inP2P;
    }

    /// STORAGE ///

    mapping(address => mapping(address => Balance)) public supplyScaledBalance; // underlying => user => balance
    mapping(address => mapping(address => Balance)) public borrowScaledBalance; // underlying => user => balance

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
        returns (address poolToken, TokenType tokenType)
    {
        poolToken = address(uint160(_id));
        uint256 firstTwoBits = _id >> 254;
        if (firstTwoBits == 0) {
            tokenType = TokenType.SUPPLY_POOL;
        } else if (firstTwoBits == 1) {
            tokenType = TokenType.SUPPLY_P2P;
        } else if (firstTwoBits == 2) {
            tokenType = TokenType.BORROW_POOL;
        } else if (firstTwoBits == 3) {
            tokenType = TokenType.BORROW_P2P;
        } else {
            revert SomethingWentWrong();
        }
    }

    /// ERC1155 ///

    function uri(uint256 id) public pure override returns (string memory) {
        return "https://morpho.xyz/supercooluri/";
    }

    function balanceOf(address _owner, uint256 _id) public view override returns (uint256) {
        (address poolToken, TokenType tokenType) = _getUnderlyingAndPositionTypeFromId(_id);
        if (tokenType == TokenType.SUPPLY_POOL) {
            return supplyScaledBalance[poolToken][_owner].onPool;
        } else if (tokenType == TokenType.SUPPLY_P2P) {
            return supplyScaledBalance[poolToken][_owner].inP2P;
        } else if (tokenType == TokenType.BORROW_POOL) {
            return borrowScaledBalance[poolToken][_owner].onPool;
        } else {
            return borrowScaledBalance[poolToken][_owner].inP2P;
        }
    }

    function setApprovalForAll(address _operator, bool _approved) public override {
        // ...
        super.setApprovalForAll(_operator, _approved);
    }

    function safeTransferFrom(address _from, address _to, uint256 id, uint256 _amount, bytes calldata _data)
        public
        override
    {
        // ...
        super.safeTransferFrom(_from, _to, id, _amount, _data);
    }

    // function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
    //     public
    //     view
    //     override
    //     returns (uint256[] memory)
    // {}

    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) public override {
        // ...
        super.safeBatchTransferFrom(_from, _to, _ids, _amounts, _data);
    }
}
