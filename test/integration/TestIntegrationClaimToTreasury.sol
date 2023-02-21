// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoStorage} from "src/MorphoStorage.sol";
import {MorphoSetters} from "src/MorphoSetters.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationFee is IntegrationTest {
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
    // Morpho Labs chooses arbitrarily Matic, The Graph, Rocket Pool(governance token), Kucoin Token and TUSD.
    function testClaimToTreasuryShouldPassIfMarketNotCreated(uint256[] calldata amounts) public {
        vm.assume(amounts.length >= allUnderlyings.length);
        address[5] memory tokenAddresses = [
            0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0,
            0xc944E90C64B2c07662A292be6244BDf05Cda44a7,
            0xD33526068D116cE69F19A9ee46F0bd304F21A51f,
            0xf34960d9d60be18cC1D5Afc1A6F012A723a28811,
            0x0000000000085d4780B73119b644AE5ecd22b376
        ];
        address[] memory underlyings = new address[](tokenAddresses.length);

        address treasuryVault = address(1);
        uint256 lengthUnderlyings;

        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            if (morpho.market(tokenAddresses[i]).aToken == address(0)) {
                underlyings[lengthUnderlyings] = tokenAddresses[i];
                deal(tokenAddresses[i], address(morpho), amounts[lengthUnderlyings]);
                ++lengthUnderlyings;
            }
        }

        morpho.setTreasuryVault(treasuryVault);
        morpho.claimToTreasury(underlyings, amounts);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (underlyings[i] != address(0)) {
                assertEq(amounts[i], ERC20(underlyings[i]).balanceOf(address(morpho)), "Incorrect Contract Balance");
            }
        }
    }

    function testClaimToTreasuryShouldPassIfAmountsClaimedEqualsZero(uint256[] calldata balanceAmounts) public {
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
            assertEq(balanceAmounts[i], ERC20(underlyings[i]).balanceOf(address(morpho)), "Incorrect Contract Balance");
        }
    }

    function testClaimToTreasury(
        uint256[] memory balanceAmounts,
        uint256[] memory idleAmounts,
        uint256[] memory claimedAmounts,
        address treasuryVault
    ) public {
        address[] memory underlyings = allUnderlyings;
        uint256[] memory beforeBalanceTreasury = new uint256[](underlyings.length);

        vm.assume(claimedAmounts.length >= underlyings.length);
        vm.assume(balanceAmounts.length >= idleAmounts.length);
        vm.assume(idleAmounts.length >= underlyings.length);
        vm.assume(treasuryVault != address(0));

        for (uint256 i = 0; i < underlyings.length; ++i) {
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
                "Expected Contract Balance!= Real Contract Balance"
            );
            assertEq(
                ERC20(underlyings[i]).balanceOf(treasuryVault) - beforeBalanceTreasury[i],
                Math.min(claimedAmounts[i], balanceAmounts[i] - morpho.market(underlyings[i]).idleSupply),
                "Expected Treasury Balance!= Real Treasury Balance"
            );
        }
    }
}
