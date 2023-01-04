// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library MarketLib {
    using SafeCast for uint256;

    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.aToken != address(0);
    }

    function getSupplyIndexes(Types.Market storage market)
        internal
        view
        returns (Types.MarketSideIndexes256 memory supplyIndexes)
    {
        supplyIndexes.poolIndex = uint256(market.indexes.supply.poolIndex);
        supplyIndexes.p2pIndex = uint256(market.indexes.supply.p2pIndex);
    }

    function getBorrowIndexes(Types.Market storage market)
        internal
        view
        returns (Types.MarketSideIndexes256 memory borrowIndexes)
    {
        borrowIndexes.poolIndex = uint256(market.indexes.borrow.poolIndex);
        borrowIndexes.p2pIndex = uint256(market.indexes.borrow.p2pIndex);
    }

    function getIndexes(Types.Market storage market) internal view returns (Types.Indexes256 memory indexes) {
        indexes.supply = getSupplyIndexes(market);
        indexes.borrow = getBorrowIndexes(market);
    }

    function setIndexes(Types.Market storage market, Types.Indexes256 memory indexes) internal {
        market.indexes.supply.poolIndex = indexes.supply.poolIndex.toUint128();
        market.indexes.borrow.poolIndex = indexes.borrow.poolIndex.toUint128();
        market.indexes.supply.p2pIndex = indexes.supply.p2pIndex.toUint128();
        market.indexes.borrow.p2pIndex = indexes.borrow.p2pIndex.toUint128();
        market.lastUpdateTimestamp = uint32(block.timestamp);
    }
}
