// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMorphoSetters is IntegrationTest {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function testShouldNotCreateSiloedBorrowMarket() public {
        DataTypes.ReserveData memory reserve = pool.getReserveData(link);
        reserve.configuration.setSiloedBorrowing(true);
        vm.mockCall(address(pool), abi.encodeCall(pool.getReserveData, (link)), abi.encode(reserve));

        vm.expectRevert(Errors.SiloedBorrowMarket.selector);
        morpho.createMarket(link, 0, 0);
    }

    function testSetIsClaimRewardsPausedRevertIfCallerNotOwner(address caller, bool isPaused) public {
        vm.assume(caller != address(this));

        vm.startPrank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsClaimRewardsPaused(isPaused);
    }

    function testSetIsClaimRewardsPaused(bool isPaused) public {
        vm.expectEmit(true, true, true, true, address(morpho));
        emit Events.IsClaimRewardsPausedSet(isPaused);

        morpho.setIsClaimRewardsPaused(isPaused);
        assertEq(morpho.isClaimRewardsPaused(), isPaused);
    }
}
