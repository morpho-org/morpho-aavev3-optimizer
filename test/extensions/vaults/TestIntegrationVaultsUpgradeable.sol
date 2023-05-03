// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/extensions/vaults/TestSetupVaults.sol";

contract TestIntegrationVaultsUpgradeable is TestSetupVaults {
    using WadRayMath for uint256;

    function testUpgradeSupplyVault() public {
        SupplyVault wethSupplyVaultImplV2 = new SupplyVault(
            address(morpho)
        );

        vm.record();
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(wrappedNativeTokenSupplyVaultProxy, address(wethSupplyVaultImplV2));
        (, bytes32[] memory writes) = vm.accesses(address(wrappedNativeTokenSupplyVault));

        // 1 write for the implemention.
        assertEq(writes.length, 1);
        address newImplem = address(
            uint160(
                uint256(
                    vm.load(
                        address(wrappedNativeTokenSupplyVault),
                        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1) // Implementation slot.
                    )
                )
            )
        );
        assertEq(newImplem, address(wethSupplyVaultImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeSupplyVault() public {
        SupplyVault supplyVaultImplV2 = new SupplyVault(address(morpho));

        vm.prank(address(user));
        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(wrappedNativeTokenSupplyVaultProxy, address(supplyVaultImplV2));

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(wrappedNativeTokenSupplyVaultProxy, address(supplyVaultImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallSupplyVault() public {
        SupplyVault wethSupplyVaultImplV2 = new SupplyVault(
            address(morpho)
        );

        vm.prank(address(user));
        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(wrappedNativeTokenSupplyVaultProxy, payable(address(wethSupplyVaultImplV2)), "");

        // Revert for wrong data not wrong caller.
        vm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(wrappedNativeTokenSupplyVaultProxy, payable(address(wethSupplyVaultImplV2)), "");
    }

    function testSupplyVaultImplementationsShouldBeInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        supplyVaultImplV1.initialize(address(wNative), RECIPIENT, "MorphoAaveWETH", "maWETH", 0, 4);
    }
}