// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSetters is IntegrationTest {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function setUp() public virtual override {
        _deploy();
        _label();
    }

    function testCreateMarketFailsForZeroUnderlying(uint16 reserveFactor, uint16 p2pIndexCursor) public {
        vm.assume(reserveFactor <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(p2pIndexCursor <= PercentageMath.PERCENTAGE_FACTOR);

        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.createMarket(address(0), reserveFactor, p2pIndexCursor);
    }

    function testCreateMarketFailsIfReserveNotActive(uint16 reserveFactor, uint16 p2pIndexCursor) public {
        vm.assume(reserveFactor <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(p2pIndexCursor <= PercentageMath.PERCENTAGE_FACTOR);

        vm.expectRevert(Errors.MarketIsNotListedOnAave.selector);
        morpho.createMarket(address(1), reserveFactor, p2pIndexCursor);
    }

    function testCreateMarketFailsIfMarketAlreadyCreated(
        uint16 reserveFactor1,
        uint16 reserveFactor2,
        uint16 p2pIndexCursor1,
        uint16 p2pIndexCursor2
    ) public {
        vm.assume(reserveFactor1 <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(reserveFactor2 <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(p2pIndexCursor1 <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(p2pIndexCursor2 <= PercentageMath.PERCENTAGE_FACTOR);
        morpho.createMarket(dai, reserveFactor1, p2pIndexCursor1);
        vm.expectRevert(Errors.MarketAlreadyCreated.selector);
        morpho.createMarket(dai, reserveFactor2, p2pIndexCursor2);
    }

    function testCreateMarket(uint16 reserveFactor, uint16 p2pIndexCursor) public {
        vm.assume(reserveFactor <= PercentageMath.PERCENTAGE_FACTOR);
        vm.assume(p2pIndexCursor <= PercentageMath.PERCENTAGE_FACTOR);

        morpho.createMarket(dai, reserveFactor, p2pIndexCursor);
        // incomplete
    }

    function testClaimToTreasury() public {}

    function testIncreaseP2PDeltas() public {}

    function testSetDefaultIterations() public {}

    function testSetPositionsManager() public {}

    function testSetRewardsManager() public {}

    function testSetTreasuryVault() public {}

    function testSetReserveFactor() public {}

    function testSetP2PIndexCursor() public {}

    function testSetIsSupplyPaused() public {}

    function testSetIsSupplyCollateralPaused() public {}

    function testSetIsBorrowPaused() public {}

    function testSetIsRepayPaused() public {}

    function testSetIsWithdrawPaused() public {}

    function testSetIsWithdrawCollateralPaused() public {}

    function testSetIsLiquidateCollateralPaused() public {}

    function testSetIsLiquidateBorrowPaused() public {}

    function testSetIsPaused() public {}

    function testSetIsPausedForAllMarkets() public {}

    function testSetIsP2PDisabled() public {}

    function testSetIsDeprecated() public {}
}
