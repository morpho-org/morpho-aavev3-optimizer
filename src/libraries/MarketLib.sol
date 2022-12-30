// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library MarketLib {
    using SafeCast for uint256;

    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.aToken != address(0);
    }

    function isCreatedMem(Types.Market memory market) internal pure returns (bool) {
        return market.aToken != address(0);
    }

    function getIndexes(Types.Market storage market) internal view returns (Types.Indexes256 memory indexes) {
        indexes.poolSupplyIndex = uint256(market.indexes.poolSupplyIndex);
        indexes.poolBorrowIndex = uint256(market.indexes.poolBorrowIndex);
        indexes.p2pSupplyIndex = uint256(market.indexes.p2pSupplyIndex);
        indexes.p2pBorrowIndex = uint256(market.indexes.p2pBorrowIndex);
    }

    function setIndexes(Types.Market storage market, Types.Indexes256 memory indexes) internal {
        market.indexes.poolSupplyIndex = indexes.poolSupplyIndex.toUint128();
        market.indexes.poolBorrowIndex = indexes.poolBorrowIndex.toUint128();
        market.indexes.p2pSupplyIndex = indexes.p2pSupplyIndex.toUint128();
        market.indexes.p2pBorrowIndex = indexes.p2pBorrowIndex.toUint128();
        market.lastUpdateTimestamp = block.timestamp.toUint32();
    }
}
