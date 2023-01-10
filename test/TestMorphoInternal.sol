// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {MorphoStorage} from "../src/MorphoStorage.sol";
import {MorphoInternal} from "../src/MorphoInternal.sol";

import "./setup/TestSetup.sol";

contract TestMorphoInternal is TestSetup, MorphoInternal {
    using TestConfig for TestConfig.Config;

    constructor() MorphoStorage(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function testSetPauseStatus() public {
        Types.PauseStatuses storage pauseStatuses = _market[dai].pauseStatuses;
        assertEq(pauseStatuses.isSupplyPaused, false);

        _setPauseStatus(dai, true);

        assertEq(pauseStatuses.isSupplyPaused, true);
    }

    function testApproveManager(address owner, address manager, bool isAllowed) public {
        _approveManager(owner, manager, isAllowed);
        assertEq(_isManaging[owner][manager], isAllowed);
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
}
