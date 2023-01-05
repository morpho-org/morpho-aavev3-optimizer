// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {Test} from "@forge-std/Test.sol";
import {console2} from "@forge-std/console2.sol";

import {MorphoStorage} from "../src/MorphoStorage.sol";
import {MorphoInternal} from "../src/MorphoInternal.sol";
import {Types} from "../src/libraries/Types.sol";

contract TestMorphoInternal is MorphoInternal, Test {
    /// CONSTRUCTOR ///

    constructor() MorphoStorage(address(0x4001), address(0xADD)) {}

    /// TESTS TO ADD:

    // _computeIndexes
    // _updateIndexes
    // _getUserSupplyBalanceFromIndexes
    // _getUserBorrowBalanceFromIndexes
    // _getUserSupplyBalance
    // _getUserBorrowBalance

    // _assetLiquidityData
    // _liquidityDataCollateral
    // _liquidityDataDebt
    // _liquidityData

    // _updateInDS
    // _updateSupplierInDS
    // _updateBorrowerInDS

    // _setPauseStatus
}
