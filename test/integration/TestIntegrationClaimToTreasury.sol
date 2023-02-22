// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationClaimToTreasury is IntegrationTest {
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using Math for uint256;
    using WadRayMath for uint256;

    function testClaimToTreasuryShouldRevertIfTreasuryVaultIsZero(uint256[] calldata amounts) public {
        address[] memory underlyings;

        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.claimToTreasury(underlyings, amounts);
    }

    // @dev The test assumes that at least one the five tokens used is not listed on Morpho, otherwise the test is useless.
    // Morpho Labs choses arbitrarily Matic, The Graph, Rocket Pool(governance token), Kucoin Token and TUSD.
    function testShouldClaimToTreasuryIfMarketNotCreated(uint256[] calldata amounts) public {
        vm.assume(amounts.length >= allUnderlyings.length);

        address[] memory underlyings = new address[](marketsNotCreated.length);

        address treasuryVault = address(1);
        uint256 lengthUnderlyings;

        for (uint256 i = 0; i < marketsNotCreated.length; ++i) {
            if (morpho.market(marketsNotCreated[i]).aToken == address(0)) {
                underlyings[lengthUnderlyings] = marketsNotCreated[i];
                deal(marketsNotCreated[i], address(morpho), amounts[lengthUnderlyings]);
                ++lengthUnderlyings;
            }
        }

        morpho.setTreasuryVault(treasuryVault);
        morpho.claimToTreasury(underlyings, amounts);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (underlyings[i] != address(0)) {
                assertEq(amounts[i], ERC20(underlyings[i]).balanceOf(address(morpho)), "Incorrect contract balance");
            }
        }
    }

    function testClaimToTreasuryShouldPassIfZeroUnderlyings(
        uint256[] calldata claimedAmounts,
        uint256[] calldata balanceAmounts
    ) public {
        address[] memory underlyings;
        uint256[] memory beforeBalanceTreasury = new uint256[](allUnderlyings.length);
        address treasuryVault = address(1);
        vm.assume(claimedAmounts.length >= allUnderlyings.length);
        vm.assume(balanceAmounts.length >= allUnderlyings.length);
        morpho.setTreasuryVault(treasuryVault);

        for (uint256 i = 0; i < allUnderlyings.length; ++i) {
            deal(allUnderlyings[i], address(morpho), balanceAmounts[i]);
            beforeBalanceTreasury[i] = ERC20(allUnderlyings[i]).balanceOf(treasuryVault);
        }
        morpho.claimToTreasury(underlyings, claimedAmounts);

        for (uint256 i = 0; i < allUnderlyings.length; ++i) {
            assertEq(
                balanceAmounts[i], ERC20(allUnderlyings[i]).balanceOf(address(morpho)), "Incorrect contract balance"
            );
            assertEq(
                beforeBalanceTreasury[i],
                ERC20(allUnderlyings[i]).balanceOf(treasuryVault),
                "Incorrect treasury balance"
            );
        }
    }

    function testClaimToTreasuryShouldPassIfAmountsClaimedEqualZero(uint256[] calldata balanceAmounts) public {
        uint256[] memory claimedAmounts = new uint256[](balanceAmounts.length);
        address[] memory underlyings = allUnderlyings;
        address treasuryVault = address(1);
        vm.assume(balanceAmounts.length >= underlyings.length);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            deal(underlyings[i], address(morpho), balanceAmounts[i]);
        }

        morpho.setTreasuryVault(treasuryVault);
        morpho.claimToTreasury(underlyings, claimedAmounts);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(balanceAmounts[i], ERC20(underlyings[i]).balanceOf(address(morpho)), "Incorrect contract balance");
        }
    }

    function testClaimToTreasury(
        uint256[] memory balanceAmounts,
        uint256[] memory idleAmounts,
        uint256[] memory claimedAmounts
    ) public {
        address treasuryVault = address(1);
        address[] memory underlyings = allUnderlyings;
        uint256[] memory beforeBalanceTreasury = new uint256[](underlyings.length);

        vm.assume(claimedAmounts.length >= underlyings.length);
        vm.assume(balanceAmounts.length >= idleAmounts.length);
        vm.assume(idleAmounts.length >= underlyings.length);
        vm.assume(treasuryVault != address(0));

        for (uint256 i = 0; i < underlyings.length; ++i) {
            balanceAmounts[i] =
                bound(balanceAmounts[i], 0, type(uint256).max - ERC20(underlyings[i]).balanceOf(treasuryVault));
            idleAmounts[i] = bound(idleAmounts[i], 0, balanceAmounts[i]);
            morpho.market(underlyings[i]).idleSupply = idleAmounts[i];
            morpho.market(underlyings[i]).aToken = address(1);
            deal(underlyings[i], address(morpho), balanceAmounts[i]);
        }

        morpho.setTreasuryVault(treasuryVault);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (claimedAmounts[i] > 0 && balanceAmounts[i] - morpho.market(underlyings[i]).idleSupply > 0) {
                vm.expectEmit(true, true, true, true);
                emit Events.ReserveFeeClaimed(
                    underlyings[i],
                    Math.min(claimedAmounts[i], balanceAmounts[i] - morpho.market(underlyings[i]).idleSupply)
                    );
            }
            beforeBalanceTreasury[i] = ERC20(underlyings[i]).balanceOf(treasuryVault);
        }

        morpho.claimToTreasury(underlyings, claimedAmounts);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(
                ERC20(underlyings[i]).balanceOf(address(morpho)) - morpho.market(underlyings[i]).idleSupply,
                (balanceAmounts[i] - morpho.market(underlyings[i]).idleSupply).zeroFloorSub(claimedAmounts[i]),
                "Expected contract balance != Real contract balance"
            );
            assertEq(
                ERC20(underlyings[i]).balanceOf(treasuryVault) - beforeBalanceTreasury[i],
                Math.min(claimedAmounts[i], balanceAmounts[i] - morpho.market(underlyings[i]).idleSupply),
                "Expected treasury balance != Real treasury balance"
            );
        }
    }
}
