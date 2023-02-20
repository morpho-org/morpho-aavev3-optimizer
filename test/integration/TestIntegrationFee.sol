pragma solidity ^0.8.17;

import {TestConfig, TestConfigLib} from "test/helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {MorphoStorage} from "src/MorphoStorage.sol";
import {MorphoSetters} from "src/MorphoSetters.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationFee is IntegrationTest, MorphoSetters {
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using Math for uint256;
    using WadRayMath for uint256;

    constructor() MorphoStorage(_initConfig().getAddressesProvider(), 0) {}

    function setUp() public virtual override {
        super.setUp();
    }

    function testClaimToTreasuryShouldRevertIfTreasuryVaultIsZero(uint256[] calldata amounts) public {
        address[] memory underlyings;

        vm.prank(this.owner());
        vm.expectRevert(Errors.AddressIsZero.selector);
        this.claimToTreasury(underlyings, amounts);
    }

    function testClaimToTreasuryShouldPassIfMarketNotCreated(uint256[] calldata amounts) public {
        vm.assume(amounts.length >= allUnderlyings.length);
        address[] memory underlyings = allUnderlyings;
        address treasuryVault = address(1);
        for (uint256 i = 0; i < underlyings.length; ++i) {
            Types.Market storage underlyingMarket = _market[underlyings[i]];

            underlyingMarket.aToken = address(0);
            deal(underlyings[i], address(this), amounts[i]);
        }

        vm.startPrank(this.owner());
        this.setTreasuryVault(treasuryVault);
        this.claimToTreasury(underlyings, amounts);
        vm.stopPrank();

        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(amounts[i], ERC20(underlyings[i]).balanceOf(address(this)), "Incorrect balance");
        }
    }

    function testClaimToTreasuryShouldPassIfAmountsClaimedEqualsZero(uint256[] calldata balanceAmounts) public {
        uint256[] memory claimedAmounts = new uint256[](balanceAmounts.length);
        address[] memory underlyings = allUnderlyings;
        address treasuryVault = address(1);
        vm.assume(balanceAmounts.length >= underlyings.length);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            deal(underlyings[i], address(this), balanceAmounts[i]);
            _market[underlyings[i]].aToken = address(2);
        }

        vm.startPrank(this.owner());
        this.setTreasuryVault(treasuryVault);
        this.claimToTreasury(underlyings, claimedAmounts);
        vm.stopPrank();

        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(balanceAmounts[i], ERC20(underlyings[i]).balanceOf(address(this)), "Incorrect balance");
        }
    }

    function testClaimToTreasury(
        uint256[] memory balanceAmounts,
        uint256[] memory idleAmounts,
        uint256[] memory claimedAmounts,
        address treasuryVault
    ) public {
        address[] memory underlyings = allUnderlyings;

        vm.assume(claimedAmounts.length >= underlyings.length);
        vm.assume(balanceAmounts.length >= idleAmounts.length);
        vm.assume(idleAmounts.length >= underlyings.length);
        vm.assume(treasuryVault != address(0));

        for (uint256 i = 0; i < underlyings.length; ++i) {
            idleAmounts[i] = bound(idleAmounts[i], 0, balanceAmounts[i]);
            _market[underlyings[i]].idleSupply = idleAmounts[i];
            _market[underlyings[i]].aToken = address(1);
            deal(underlyings[i], address(this), balanceAmounts[i]);
        }

        vm.startPrank(this.owner());
        this.setTreasuryVault(treasuryVault);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (claimedAmounts[i] > 0 && balanceAmounts[i] - _market[underlyings[i]].idleSupply > 0) {
                vm.expectEmit(true, true, false, false);
                emit Events.ReserveFeeClaimed(
                    underlyings[i], Math.min(claimedAmounts[i], balanceAmounts[i] - _market[underlyings[i]].idleSupply)
                    );
            }
        }

        this.claimToTreasury(underlyings, claimedAmounts);
        vm.stopPrank();

        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(
                ERC20(underlyings[i]).balanceOf(address(this)) - _market[underlyings[i]].idleSupply,
                (balanceAmounts[i] - _market[underlyings[i]].idleSupply).zeroFloorSub(claimedAmounts[i]),
                "Expected Contract Balance!= Real Contract Balance"
            );
            assertEq(
                ERC20(underlyings[i]).balanceOf(treasuryVault),
                Math.min(claimedAmounts[i], balanceAmounts[i] - _market[underlyings[i]].idleSupply),
                "Expected Treasury Balance!= Real Treasury Balance"
            );
        }
    }
}
