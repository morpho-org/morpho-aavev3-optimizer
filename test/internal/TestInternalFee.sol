pragma solidity ^0.8.17;

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {PoolLib} from "src/libraries/PoolLib.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "src/libraries/MarketBalanceLib.sol";

import {MorphoStorage} from "src/MorphoStorage.sol";
import {MorphoSetters} from "src/MorphoSetters.sol";
import "test/helpers/InternalTest.sol";

contract TestInternalFee is InternalTest, MorphoSetters {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using PoolLib for IPool;

    function setUp() public virtual override {
        super.setUp();

        _defaultIterations = Types.Iterations(10, 10);

        _createMarket(dai, 0, 3_333);
        _createMarket(wbtc, 0, 3_333);
        _createMarket(usdc, 0, 3_333);
        _createMarket(wNative, 0, 3_333);

        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);
    }

    function testClaimToTreasuryShouldRevertIfTreasuryVaultIsZero(uint256[] calldata amounts) public {
        vm.startPrank(this.owner());
        this.setTreasuryVault(address(0));
        address[] memory underlyings;
        vm.expectRevert(Errors.AddressIsZero.selector);
        this.claimToTreasury(underlyings, amounts);
        vm.stopPrank();
    }

    function testClaimToTreasuryShouldPassIfMarketNotCreated(uint256[] calldata amounts, address treasuryVault)
        public
    {
        vm.assume(amounts.length >= allUnderlyings.length);
        address[] memory underlyings = allUnderlyings;
        console.log(amounts.length);
        for (uint256 i = 0; i < underlyings.length; ++i) {
            Types.Market storage underlyingMarket = _market[underlyings[i]];

            underlyingMarket.aToken = address(0);
            deal(underlyings[i], address(this), amounts[i]);
            console.log(ERC20(underlyings[i]).balanceOf(address(this)), amounts[i], underlyings[i]);
        }
        vm.assume(treasuryVault != address(0));
        vm.startPrank(this.owner());
        this.setTreasuryVault(treasuryVault);
        this.claimToTreasury(underlyings, amounts);
        vm.stopPrank();
        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertEq(amounts[i], ERC20(underlyings[i]).balanceOf(address(this)), "Incorrect balance");
        }
    }

    function testClaimToTreasuryShouldPassIfAmountsClaimedEqualsZero(
        uint256[] calldata balanceAmounts,
        address treasuryVault
    ) public {
        uint256[] memory claimedAmounts = new uint256[](balanceAmounts.length);
        address[] memory underlyings = allUnderlyings;

        vm.assume(balanceAmounts.length >= underlyings.length);
        for (uint256 i = 0; i < underlyings.length; ++i) {
            deal(underlyings[i], address(this), balanceAmounts[i]);
            _market[underlyings[i]].aToken = address(1);
        }
        vm.assume(treasuryVault != address(0));
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
        for (uint256 i = 0; i < underlyings.length; ++i) {
            idleAmounts[i] = bound(idleAmounts[i], 0, balanceAmounts[i]);
            _market[underlyings[i]].idleSupply = idleAmounts[i];
            _market[underlyings[i]].aToken = address(1);
            deal(underlyings[i], address(this), balanceAmounts[i]);
        }
        vm.assume(treasuryVault != address(0));
        vm.startPrank(this.owner());
        this.setTreasuryVault(treasuryVault);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (claimedAmounts[i] > 0 && balanceAmounts[i] - _market[underlyings[i]].idleSupply > 0) {
                vm.expectEmit(true, false, false, false);
                emit Events.ReserveFeeClaimed(underlyings[i], 0);
            }
        }

        this.claimToTreasury(underlyings, claimedAmounts);
        vm.stopPrank();
        for (uint256 i = 0; i < underlyings.length; ++i) {
            assertApproxEqAbs(
                ERC20(underlyings[i]).balanceOf(address(this)) - _market[underlyings[i]].idleSupply,
                (balanceAmounts[i] - _market[underlyings[i]].idleSupply).zeroFloorSub(claimedAmounts[i]),
                2,
                "Incorrect balance"
            );
        }
    }
}
