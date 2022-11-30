// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC1155.sol";

contract Morpho is ERC1155 {
    /// STRUCTS ///

    struct Balance {
        uint128 inP2P;
        uint128 onPool;
    }

    /// STORAGE ///

    mapping(address => mapping(address => Balance)) public supplyScaledBalance;
    mapping(address => mapping(address => Balance)) public borrowScaledBalance;

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

    /// ERC11555 ///

    function uri(uint256 id) public pure override returns (string memory) {
        return "https://morpho.xyz/supercoolnft/";
    }
}
