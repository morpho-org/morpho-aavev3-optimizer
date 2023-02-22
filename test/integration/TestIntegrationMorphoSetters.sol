// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMorphoSetters is IntegrationTest {
    function testSetIsClaimRewardsPausedRevertIfCallerNotOwner(address caller, bool isPaused) public {
        vm.assume(caller != Morpho(address(morpho)).owner());

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
