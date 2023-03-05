// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSetters is IntegrationTest {
    function setUp() public virtual override {
        _deploy();
    }

    modifier testOnlyOwner() {
        vm.prank(address(42069));
        vm.expectRevert("Ownable: caller is not the owner");
        _;
    }

    function testCreateMarketRevertsIfNotOwner() public testOnlyOwner {
        morpho.createMarket(dai, 1000, 1000);
    }

    function testCreateMarketRevertsIfZeroAddressUnderlying() public {
        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.createMarket(address(0), 1000, 1000);
    }

    function testCreateMarketRevertsIfMarketNotOnAave() public {
        vm.expectRevert(Errors.MarketIsNotListedOnAave.selector);
        morpho.createMarket(address(42069), 1000, 1000);
    }

    function testCreateMarketRevertsIfMarketAlreadyCreated() public {
        morpho.createMarket(dai, 1000, 1000);
        vm.expectRevert(Errors.MarketAlreadyCreated.selector);
        morpho.createMarket(dai, 1000, 1000);
    }

    function testCreateMarket(uint256 seed) public {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.MarketCreated(underlying);
        morpho.createMarket(underlying, 1000, 1000);
    }

    function testClaimToTreasuryOnlyOwner() public testOnlyOwner {
        address[] memory underlyings = new address[](1);
        underlyings[0] = dai;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        morpho.claimToTreasury(underlyings, amounts);
    }

    function testIncreaseP2PDeltas() public {}

    function testSetDefaultIterations() public {}

    function testSetPositionsManager() public {}

    function testSetRewardsManager() public {}

    function testSetTreasuryVault() public {}

    function testSetReserveFactor() public {}

    function testSetP2PIndexCursor() public {}

    function testSetIsClaimRewardsPaused() public {}

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
