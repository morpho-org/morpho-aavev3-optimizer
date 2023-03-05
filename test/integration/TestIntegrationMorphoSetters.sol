// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMorphoSetters is IntegrationTest {
    function setUp() public virtual override {
        _deploy();
    }

    modifier testOnlyOwner() {
        vm.prank(address(42069));
        vm.expectRevert("Ownable: caller is not the owner");
        _;
    }

    function testCreateMarketRevertsIfNotOwner(uint256 seed, uint16 reserveFactor, uint16 p2pIndexCursor)
        public
        testOnlyOwner
    {
        address underlying = _randomUnderlying(seed);
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));
        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function testCreateMarketRevertsIfZeroAddressUnderlying(uint16 reserveFactor, uint16 p2pIndexCursor) public {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));
        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.createMarket(address(0), reserveFactor, p2pIndexCursor);
    }

    function _containsUnderlying(address underlying) internal view returns (bool) {
        for (uint256 i; i < allUnderlyings.length; i++) {
            if (allUnderlyings[i] == underlying) {
                return true;
            }
        }
        return false;
    }

    function testCreateMarketRevertsIfMarketNotOnAave(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor)
        public
    {
        vm.assume(!_containsUnderlying(underlying));
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));
        vm.expectRevert(Errors.MarketIsNotListedOnAave.selector);
        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    function testCreateMarketRevertsIfMarketAlreadyCreated(
        uint256 seed,
        uint16 reserveFactor1,
        uint16 p2pIndexCursor1,
        uint16 reserveFactor2,
        uint16 p2pIndexCursor2
    ) public {
        address underlying = _randomUnderlying(seed);
        reserveFactor1 = uint16(bound(reserveFactor1, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor1 = uint16(bound(p2pIndexCursor1, 0, PercentageMath.PERCENTAGE_FACTOR));
        reserveFactor2 = uint16(bound(reserveFactor2, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor2 = uint16(bound(p2pIndexCursor2, 0, PercentageMath.PERCENTAGE_FACTOR));
        morpho.createMarket(underlying, reserveFactor1, p2pIndexCursor1);
        vm.expectRevert(Errors.MarketAlreadyCreated.selector);
        morpho.createMarket(underlying, reserveFactor2, p2pIndexCursor2);
    }

    function testCreateMarket(uint256 seed, uint16 reserveFactor, uint16 p2pIndexCursor) public {
        address underlying = _randomUnderlying(seed);
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        uint256 expectedPoolSupplyIndex = pool.getReserveNormalizedIncome(underlying);
        uint256 expectedPoolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlying);

        vm.expectEmit(true, true, true, true);
        emit Events.MarketCreated(underlying);
        vm.expectEmit(true, true, true, true);
        emit Events.IndexesUpdated(
            underlying, expectedPoolSupplyIndex, WadRayMath.RAY, expectedPoolBorrowIndex, WadRayMath.RAY
            );
        vm.expectEmit(true, true, true, true);
        emit Events.ReserveFactorSet(underlying, reserveFactor);
        vm.expectEmit(true, true, true, true);
        emit Events.P2PIndexCursorSet(underlying, p2pIndexCursor);
        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);

        assertEq(ERC20(underlying).allowance(address(morpho), address(pool)), type(uint256).max);
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
