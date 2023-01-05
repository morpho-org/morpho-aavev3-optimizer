// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {Test} from "@forge-std/Test.sol";
import {console2} from "@forge-std/console2.sol";

import {MorphoStorage} from "../src/MorphoStorage.sol";
import {MorphoInternal} from "../src/MorphoInternal.sol";
import {Types} from "../src/libraries/Types.sol";

contract TestMorphoInternal is MorphoInternal, Test {
    uint256 public constant positionMax = uint256(type(Types.PositionType).max);

    /// CONSTRUCTOR ///

    constructor() MorphoStorage(address(1)) {}

    function testDecodeId(uint256 id) public {
        vm.assume((id >> 252) <= positionMax);
        (address underlying, Types.PositionType positionType) = _decodeId(id);
        assertEq(underlying, address(uint160(id)));
        assertEq(uint256(positionType), id >> 252);
    }

    function testReverseDecodeId(address underlying, uint256 positionType) public {
        positionType = positionType % (positionMax + 1);
        uint256 id = uint256(uint160(underlying)) + (positionType << 252);
        (address decodedUnderlying, Types.PositionType decodedPositionType) = _decodeId(id);
        assertEq(decodedUnderlying, underlying);
        assertEq(uint256(decodedPositionType), positionType);
    }

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
