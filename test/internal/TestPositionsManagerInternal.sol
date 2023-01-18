// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Errors} from "src/libraries/Errors.sol";
import {MorphoStorage} from "src/MorphoStorage.sol";
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";

import "test/helpers/InternalTest.sol";

contract TestInternalPositionsManagerInternal is InternalTest, PositionsManagerInternal {
    function testValidatePermission(address owner, address manager) public {
        _validatePermission(owner, owner);

        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }

        _approveManager(owner, manager, true);
        _validatePermission(owner, manager);

        _approveManager(owner, manager, false);
        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }
    }
}
