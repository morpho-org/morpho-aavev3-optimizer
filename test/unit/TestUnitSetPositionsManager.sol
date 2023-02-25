// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {PositionsManager} from "src/PositionsManager.sol";

import "test/mocks/AddressesProviderMock.sol";
import "test/helpers/InternalTest.sol";

contract TestUnitSetPositionsManager is InternalTest {
    function testSetPositionsManagerWithSameAddressesProviderAndEMode() public {
        PositionsManager positionsManager =
            new PositionsManager(this.ADDRESSES_PROVIDER(), uint8(this.E_MODE_CATEGORY_ID()));

        vm.prank(Morpho(this).owner());
        this.setPositionsManager(address(positionsManager));

        assertEq(this.positionsManager(), address(positionsManager));
    }

    function testSetPositionsManagerWithSameEModeButInconsistentAddressesProvider() public {
        AddressesProviderMock addressesProvider = new AddressesProviderMock();

        PositionsManager positionsManager =
            new PositionsManager(address(addressesProvider), uint8(this.E_MODE_CATEGORY_ID()));

        vm.prank(Morpho(this).owner());
        vm.expectRevert(Errors.InconsistentAddressesProvider.selector);
        this.setPositionsManager(address(positionsManager));
    }

    function testSetPositionsManagerWithSameAddressesProviderButInconsistentEMode(uint8 eMode) public {
        vm.assume(eMode != uint8(this.E_MODE_CATEGORY_ID()));

        PositionsManager positionsManager = new PositionsManager(this.ADDRESSES_PROVIDER(), eMode);

        vm.prank(Morpho(this).owner());
        vm.expectRevert(Errors.InconsistentEMode.selector);
        this.setPositionsManager(address(positionsManager));
    }
}
