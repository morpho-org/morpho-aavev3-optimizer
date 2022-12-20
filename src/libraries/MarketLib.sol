// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin-contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

library MarketLib {
    using SafeCast for uint256;

    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.underlying != address(0);
    }

    function isCreatedMem(Types.Market memory market) internal pure returns (bool) {
        return market.underlying != address(0);
    }

    function getIndexes(Types.Market storage market)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex, uint256 p2pSupplyIndex, uint256 p2pBorrowIndex)
    {
        poolSupplyIndex = uint256(market.poolSupplyIndex);
        poolBorrowIndex = uint256(market.poolBorrowIndex);
        p2pSupplyIndex = uint256(market.p2pSupplyIndex);
        p2pBorrowIndex = uint256(market.p2pBorrowIndex);
    }

    function setIndexes(
        Types.Market storage market,
        uint256 poolSupplyIndex,
        uint256 poolBorrowIndex,
        uint256 p2pSupplyIndex,
        uint256 p2pBorrowIndex
    ) internal {
        market.poolSupplyIndex = poolSupplyIndex.toUint128();
        market.poolBorrowIndex = poolBorrowIndex.toUint128();
        market.p2pSupplyIndex = p2pSupplyIndex.toUint128();
        market.p2pBorrowIndex = p2pBorrowIndex.toUint128();
    }
}
