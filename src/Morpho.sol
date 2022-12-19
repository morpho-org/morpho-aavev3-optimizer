// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types, Events, Errors, MarketLib, MarketBalanceLib} from "./libraries/Libraries.sol";

import {MorphoGettersAndSetters} from "./MorphoGettersAndSetters.sol";

// import {IERC1155} from "./interfaces/IERC1155.sol";
// import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

// @note: To add: IERC1155, Ownable
contract Morpho is MorphoGettersAndSetters {
    using MarketBalanceLib for Types.MarketBalances;
    using MarketLib for Types.Market;

    /// EXTERNAL ///

    function supply(
        address _underlying,
        uint256 _amount,
        address _onBehalf,
        uint256 _nbOfLoops,
        Types.PositionType _type
    ) external returns (uint256 supplied) {}

    function borrow(address _underlying, uint256 _amount, address _onBehalf, uint256 _nbOfLoops)
        external
        returns (uint256 borrowed)
    {}

    function repay(address _underlying, uint256 _amount, address _onBehalf) external returns (uint256 repaid) {}

    function withdraw(address _underlying, uint256 _amount, address _onBehalf, address _to)
        external
        returns (uint256 withdrawn)
    {}

    function liquidate(address _collateralUnderlying, address _borrowedUnderlying, address _user, uint256 _amount)
        external
        returns (uint256 repaid, uint256 seized)
    {}
}
