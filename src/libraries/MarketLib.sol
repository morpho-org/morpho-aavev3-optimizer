// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";

library MarketLib {
    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.underlying != address(0);
    }

    function isCreatedMem(Types.Market memory market) internal pure returns (bool) {
        return market.underlying != address(0);
    }
}
