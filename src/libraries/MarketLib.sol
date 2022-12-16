// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";

library MarketLib {
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    // MARKET

    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.underlying != address(0);
    }

    function isCreatedMem(Types.Market memory market) internal pure returns (bool) {
        return market.underlying != address(0);
    }

    // MARKET BALANCES

    function scaledP2PSupplyBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.suppliersP2P.getValueOf(user);
    }

    function scaledPoolSupplyBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.suppliersPool.getValueOf(user);
    }

    function scaledP2PBorrowBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.borrowersP2P.getValueOf(user);
    }

    function scaledPoolBorrowBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.borrowersPool.getValueOf(user);
    }

    function scaledCollateralBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.collateral[user];
    }
}
