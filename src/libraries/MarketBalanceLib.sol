// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

library MarketBalanceLib {
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    function scaledP2PSupplyBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.p2pSuppliers.getValueOf(user);
    }

    function scaledPoolSupplyBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.poolSuppliers.getValueOf(user);
    }

    function scaledP2PBorrowBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.p2pBorrowers.getValueOf(user);
    }

    function scaledPoolBorrowBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.poolBorrowers.getValueOf(user);
    }

    function scaledCollateralBalance(Types.MarketBalances storage marketBalances, address user)
        internal
        view
        returns (uint256)
    {
        return marketBalances.collateral[user];
    }
}
