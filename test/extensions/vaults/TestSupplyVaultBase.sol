// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/extensions/vaults/TestSetupVaults.sol";

contract TestSupplyVaultBase is TestSetupVaults {
    function testShouldTransferRewardsToRecipient(address caller, uint256 amount) public {
        vm.assume(amount > 0);

        assertEq(ERC20(MORPHO_TOKEN).balanceOf(RECIPIENT), 0);

        deal(MORPHO_TOKEN, address(daiSupplyVault), amount);
        assertEq(ERC20(MORPHO_TOKEN).balanceOf(address(daiSupplyVault)), amount);

        vm.prank(caller);
        daiSupplyVault.transferRewards();

        assertEq(ERC20(MORPHO_TOKEN).balanceOf(address(daiSupplyVault)), 0);
        assertEq(ERC20(MORPHO_TOKEN).balanceOf(RECIPIENT), amount);
    }
}
