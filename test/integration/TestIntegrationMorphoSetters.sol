// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMorphoSetters is IntegrationTest {
    uint16 private constant DEFAULT_RESERVE_FACTOR = 1_000;
    uint16 private constant DEFAULT_P2P_INDEX_CURSOR = 1_000;
    address private constant DEFAULT_PRANKER = address(uint160(uint256(keccak256(abi.encode(42069)))));
    address private constant DEFAULT_TREASURY = address(uint160(uint256(keccak256(abi.encode(1337)))));
    uint256 private constant MAX_AMOUNT = 1e20 ether;

    function setUp() public virtual override {
        _deploy();
        user = _initUser();
        promoter1 = _initUser();
        promoter2 = _initUser();
        hacker = _initUser();
        morpho.setTreasuryVault(DEFAULT_TREASURY);
    }

    modifier callNotOwner() {
        vm.prank(DEFAULT_PRANKER);
        vm.expectRevert("Ownable: caller is not the owner");
        _;
    }

    modifier createMarkets() {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            _createTestMarket(allUnderlyings[i], 0, 33_33);
        }
        // Supply dust to make UserConfigurationMap.isUsingAsCollateralOne() always return true.
        // Necessary for idle supply manipulation.
        _deposit(testMarkets[weth], 1e12, address(morpho));
        _deposit(testMarkets[dai], 1e12, address(morpho));
        _;
    }

    function testCreateMarketRevertsIfNotOwner(uint256 seed, uint16 reserveFactor, uint16 p2pIndexCursor)
        public
        callNotOwner
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

    function testCreateMarketRevertsIfMarketNotOnAave(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor)
        public
    {
        vm.assume(!_containsUnderlying(underlying));
        vm.assume(underlying != address(0));

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

    function testClaimToTreasuryOnlyOwner() public callNotOwner {
        address[] memory underlyings = new address[](1);
        underlyings[0] = dai;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        morpho.claimToTreasury(underlyings, amounts);
    }

    function testClaimToTreasuryRevertsIfTreasuryVaultIsZero() public {
        morpho.setTreasuryVault(address(0));
        address[] memory underlyings = new address[](1);
        underlyings[0] = dai;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.claimToTreasury(underlyings, amounts);
    }

    function testClaimToTreasuryDoesNothingIfMarketNotCreated(uint256 seed, uint256 amount) public {
        morpho.setTreasuryVault(DEFAULT_TREASURY);
        address[] memory underlyings = new address[](1);
        underlyings[0] = _randomUnderlying(seed);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        deal(underlyings[0], address(morpho), amount);

        assertEq(ERC20(underlyings[0]).balanceOf(address(morpho)), amount, "morpho balance before");
        assertEq(ERC20(underlyings[0]).balanceOf(DEFAULT_TREASURY), 0, "treasury balance before");

        morpho.claimToTreasury(underlyings, amounts);

        assertEq(ERC20(underlyings[0]).balanceOf(address(morpho)), amount, "morpho balance after");
        assertEq(ERC20(underlyings[0]).balanceOf(DEFAULT_TREASURY), 0, "treasury balance after");
    }

    function testClaimToTreasury(uint256 seed, uint256 amount, uint256 balance, uint256 idleSupply)
        public
        createMarkets
    {
        amount = bound(amount, 0, MAX_AMOUNT);
        balance = bound(balance, 0, MAX_AMOUNT);
        idleSupply = bound(idleSupply, 0, MAX_AMOUNT);

        address[] memory underlyings = new address[](1);
        underlyings[0] = _randomUnderlying(seed);
        vm.assume(testMarkets[underlyings[0]].isBorrowable);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        _increaseIdleSupply(promoter1, testMarkets[underlyings[0]], idleSupply);
        // There might be rounding errors in the increase of idle supply, but this test is out of scope for dealing with that
        // So it's just reassigned here.
        idleSupply = morpho.market(underlyings[0]).idleSupply;
        balance = Math.max(balance, idleSupply);

        uint256 expectedClaimed = Math.min(amount, balance - idleSupply);

        deal(underlyings[0], address(morpho), balance);

        assertEq(ERC20(underlyings[0]).balanceOf(address(morpho)), balance, "morpho balance before");
        assertEq(ERC20(underlyings[0]).balanceOf(DEFAULT_TREASURY), 0, "treasury balance before");
        assertEq(morpho.market(underlyings[0]).idleSupply, idleSupply, "idle supply before");

        morpho.claimToTreasury(underlyings, amounts);

        assertEq(ERC20(underlyings[0]).balanceOf(address(morpho)), balance - expectedClaimed, "morpho balance after");
        assertEq(ERC20(underlyings[0]).balanceOf(DEFAULT_TREASURY), expectedClaimed, "treasury balance after");
        assertEq(morpho.market(underlyings[0]).idleSupply, idleSupply, "idle supply after");
    }

    function testSetDefaultIterationsFailsIfNotOwner(uint128 repay, uint128 withdraw) public callNotOwner {
        Types.Iterations memory iterations = Types.Iterations(repay, withdraw);
        morpho.setDefaultIterations(iterations);
    }

    function testSetDefaultIterations(uint128 repay, uint128 withdraw) public {
        Types.Iterations memory iterations = Types.Iterations(repay, withdraw);
        vm.expectEmit(true, true, true, true);
        emit Events.DefaultIterationsSet(repay, withdraw);
        morpho.setDefaultIterations(iterations);
        assertEq(morpho.defaultIterations().repay, repay);
        assertEq(morpho.defaultIterations().withdraw, withdraw);
    }

    function testSetPositionsManagerFailsIfNotOwner(address positionsManager) public callNotOwner {
        vm.assume(positionsManager != address(0));
        morpho.setPositionsManager(positionsManager);
    }

    function testSetPositionsManagerFailsIfZero() public {
        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.setPositionsManager(address(0));
    }

    function testSetPositionsManager(address positionsManager) public {
        vm.assume(positionsManager != address(0));
        vm.expectEmit(true, true, true, true);
        emit Events.PositionsManagerSet(positionsManager);
        morpho.setPositionsManager(positionsManager);
        assertEq(morpho.positionsManager(), positionsManager);
    }

    function testSetRewardsManagerFailsIfNotOwner(address rewardsManager) public callNotOwner {
        morpho.setRewardsManager(rewardsManager);
    }

    function testSetRewardsManager(address rewardsManager) public {
        vm.assume(rewardsManager != address(0));
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsManagerSet(rewardsManager);
        morpho.setRewardsManager(rewardsManager);
        assertEq(morpho.rewardsManager(), rewardsManager);
    }

    function testSetTreasuryVaultFailsIfNotOwner(address treasuryVault) public callNotOwner {
        morpho.setTreasuryVault(treasuryVault);
    }

    function testSetTreasuryVault(address treasuryVault) public {
        vm.expectEmit(true, true, true, true);
        emit Events.TreasuryVaultSet(treasuryVault);
        morpho.setTreasuryVault(treasuryVault);
        assertEq(morpho.treasuryVault(), treasuryVault);
    }

    function testSetReserveFactorFailsIfNotOwner(uint256 seed, uint16 reserveFactor)
        public
        createMarkets
        callNotOwner
    {
        address underlying = _randomUnderlying(seed);
        morpho.setReserveFactor(underlying, reserveFactor);
    }

    function testSetReserveFactorFailsIfMarketNotCreated(address underlying, uint16 reserveFactor) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setReserveFactor(underlying, reserveFactor);
    }

    function testSetReserveFactor(uint256 seed, uint16 reserveFactor) public createMarkets {
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.ReserveFactorSet(underlying, reserveFactor);
        morpho.setReserveFactor(underlying, reserveFactor);
        assertEq(morpho.market(underlying).reserveFactor, reserveFactor);
    }

    function testSetP2PIndexCursorFailsIfNotOwner(uint256 seed, uint16 p2pIndexCursor)
        public
        createMarkets
        callNotOwner
    {
        address underlying = _randomUnderlying(seed);
        morpho.setP2PIndexCursor(underlying, p2pIndexCursor);
    }

    function testSetP2PIndexCursorFailsIfMarketNotCreated(address underlying, uint16 p2pIndexCursor) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setP2PIndexCursor(underlying, p2pIndexCursor);
    }

    function testSetP2PIndexCursor(uint256 seed, uint16 p2pIndexCursor) public createMarkets {
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.P2PIndexCursorSet(underlying, p2pIndexCursor);
        morpho.setP2PIndexCursor(underlying, p2pIndexCursor);
        assertEq(morpho.market(underlying).p2pIndexCursor, p2pIndexCursor);
    }

    function testSetIsClaimRewardsPausedFailsIfNotOwner(bool paused) public callNotOwner {
        morpho.setIsClaimRewardsPaused(paused);
    }

    function testSetIsClaimRewardsPaused(bool paused) public {
        vm.expectEmit(true, true, true, true);
        emit Events.IsClaimRewardsPausedSet(paused);
        morpho.setIsClaimRewardsPaused(paused);
        assertEq(morpho.isClaimRewardsPaused(), paused);
    }

    function testSetIsSupplyPausedFailsIfNotOwner(address underlying, bool paused) public createMarkets callNotOwner {
        morpho.setIsSupplyPaused(underlying, paused);
    }

    function testSetIsSupplyPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsSupplyPaused(underlying, paused);
    }

    function testSetIsSupplyPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyPausedSet(underlying, paused);
        morpho.setIsSupplyPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isSupplyPaused, paused);
    }

    function testSetIsSupplyCollateralPausedFailsIfNotOwner(address underlying, bool paused)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsSupplyCollateralPaused(underlying, paused);
    }

    function testSetIsSupplyCollateralPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsSupplyCollateralPaused(underlying, paused);
    }

    function testSetIsSupplyCollateralPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyCollateralPausedSet(underlying, paused);
        morpho.setIsSupplyCollateralPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isSupplyCollateralPaused, paused);
    }

    function testSetIsBorrowPausedFailsIfNotOwner(address underlying, bool paused) public createMarkets callNotOwner {
        morpho.setIsBorrowPaused(underlying, paused);
    }

    function testSetIsBorrowPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsBorrowPaused(underlying, paused);
    }

    function testSetIsBorrowPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsBorrowPausedSet(underlying, paused);
        morpho.setIsBorrowPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isBorrowPaused, paused);
    }

    function testSetIsRepayPausedFailsIfNotOwner(address underlying, bool paused) public createMarkets callNotOwner {
        morpho.setIsRepayPaused(underlying, paused);
    }

    function testSetIsRepayPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsRepayPaused(underlying, paused);
    }

    function testSetIsRepayPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsRepayPausedSet(underlying, paused);
        morpho.setIsRepayPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isRepayPaused, paused);
    }

    function testSetIsWithdrawPausedFailsIfNotOwner(address underlying, bool paused)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsWithdrawPaused(underlying, paused);
    }

    function testSetIsWithdrawPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsWithdrawPaused(underlying, paused);
    }

    function testSetIsWithdrawPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawPausedSet(underlying, paused);
        morpho.setIsWithdrawPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isWithdrawPaused, paused);
    }

    function testSetIsWithdrawCollateralPausedFailsIfNotOwner(address underlying, bool paused)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsWithdrawCollateralPaused(underlying, paused);
    }

    function testSetIsWithdrawCollateralPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsWithdrawCollateralPaused(underlying, paused);
    }

    function testSetIsWithdrawCollateralPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawCollateralPausedSet(underlying, paused);
        morpho.setIsWithdrawCollateralPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isWithdrawCollateralPaused, paused);
    }

    function testSetIsLiquidateCollateralPausedFailsIfNotOwner(address underlying, bool paused)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsLiquidateCollateralPaused(underlying, paused);
    }

    function testSetIsLiquidateCollateralPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsLiquidateCollateralPaused(underlying, paused);
    }

    function testSetIsLiquidateCollateralPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateCollateralPausedSet(underlying, paused);
        morpho.setIsLiquidateCollateralPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isLiquidateCollateralPaused, paused);
    }

    function testSetIsLiquidateBorrowPausedFailsIfNotOwner(address underlying, bool paused)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsLiquidateBorrowPaused(underlying, paused);
    }

    function testSetIsLiquidateBorrowPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsLiquidateBorrowPaused(underlying, paused);
    }

    function testSetIsLiquidateBorrowPaused(uint256 seed, bool paused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateBorrowPausedSet(underlying, paused);
        morpho.setIsLiquidateBorrowPaused(underlying, paused);
        assertEq(morpho.market(underlying).pauseStatuses.isLiquidateBorrowPaused, paused);
    }

    function testSetIsPausedFailsIfNotOwner(address underlying, bool paused) public createMarkets callNotOwner {
        morpho.setIsPaused(underlying, paused);
    }

    function testSetIsPausedFailsIfMarketNotCreated(address underlying, bool paused) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsPaused(underlying, paused);
    }

    function testSetIsPaused(uint256 seed, bool isPaused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsRepayPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateBorrowPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsBorrowPausedSet(underlying, isPaused);

        morpho.setIsPaused(underlying, isPaused);

        Types.PauseStatuses memory pauseStatuses = morpho.market(underlying).pauseStatuses;
        assertEq(pauseStatuses.isSupplyPaused, isPaused);
        assertEq(pauseStatuses.isSupplyCollateralPaused, isPaused);
        assertEq(pauseStatuses.isRepayPaused, isPaused);
        assertEq(pauseStatuses.isWithdrawPaused, isPaused);
        assertEq(pauseStatuses.isWithdrawCollateralPaused, isPaused);
        assertEq(pauseStatuses.isLiquidateCollateralPaused, isPaused);
        assertEq(pauseStatuses.isLiquidateBorrowPaused, isPaused);
        assertEq(pauseStatuses.isBorrowPaused, isPaused);
    }

    function testSetIsPausedDoesNotSetBorrowPauseIfDeprecated(uint256 seed, bool isPaused) public createMarkets {
        address underlying = _randomUnderlying(seed);
        morpho.setIsBorrowPaused(underlying, true);
        morpho.setIsDeprecated(underlying, true);

        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsSupplyCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsRepayPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsWithdrawCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateCollateralPausedSet(underlying, isPaused);
        vm.expectEmit(true, true, true, true);
        emit Events.IsLiquidateBorrowPausedSet(underlying, isPaused);

        morpho.setIsPaused(underlying, isPaused);

        Types.PauseStatuses memory pauseStatuses = morpho.market(underlying).pauseStatuses;

        assertEq(pauseStatuses.isSupplyPaused, isPaused);
        assertEq(pauseStatuses.isSupplyCollateralPaused, isPaused);
        assertEq(pauseStatuses.isRepayPaused, isPaused);
        assertEq(pauseStatuses.isWithdrawPaused, isPaused);
        assertEq(pauseStatuses.isWithdrawCollateralPaused, isPaused);
        assertEq(pauseStatuses.isLiquidateCollateralPaused, isPaused);
        assertEq(pauseStatuses.isLiquidateBorrowPaused, isPaused);
        assertEq(pauseStatuses.isBorrowPaused, true);
    }

    function testSetIsPausedForAllMarketsFailsIfNotOwner(bool isPaused) public createMarkets callNotOwner {
        morpho.setIsPausedForAllMarkets(isPaused);
    }

    function testSetIsPausedForAllMarkets(bool isPaused) public createMarkets {
        address[] memory markets = morpho.marketsCreated();

        for (uint256 i; i < markets.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit Events.IsSupplyPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsSupplyCollateralPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsRepayPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsWithdrawPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsWithdrawCollateralPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsLiquidateCollateralPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsLiquidateBorrowPausedSet(markets[i], isPaused);
            vm.expectEmit(true, true, true, true);
            emit Events.IsBorrowPausedSet(markets[i], isPaused);
        }

        morpho.setIsPausedForAllMarkets(isPaused);

        for (uint256 i; i < markets.length; i++) {
            Types.PauseStatuses memory pauseStatuses = morpho.market(markets[i]).pauseStatuses;
            assertEq(pauseStatuses.isSupplyPaused, isPaused);
            assertEq(pauseStatuses.isSupplyCollateralPaused, isPaused);
            assertEq(pauseStatuses.isRepayPaused, isPaused);
            assertEq(pauseStatuses.isWithdrawPaused, isPaused);
            assertEq(pauseStatuses.isWithdrawCollateralPaused, isPaused);
            assertEq(pauseStatuses.isLiquidateCollateralPaused, isPaused);
            assertEq(pauseStatuses.isLiquidateBorrowPaused, isPaused);
            assertEq(pauseStatuses.isBorrowPaused, isPaused);
        }
    }

    function testSetIsP2PDisabledFailsIfNotOwner(address underlying, bool disabled) public createMarkets callNotOwner {
        morpho.setIsP2PDisabled(underlying, disabled);
    }

    function testSetIsP2PDisabledFailsIfMarketNotCreated(address underlying, bool disabled) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsP2PDisabled(underlying, disabled);
    }

    function testSetIsP2PDisabled(uint256 seed, bool disabled) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectEmit(true, true, true, true);
        emit Events.IsP2PDisabledSet(underlying, disabled);
        morpho.setIsP2PDisabled(underlying, disabled);
        assertEq(morpho.market(underlying).pauseStatuses.isP2PDisabled, disabled);
    }

    function testSetIsDeprecatedFailsIfNotOwner(address underlying, bool deprecated)
        public
        createMarkets
        callNotOwner
    {
        morpho.setIsDeprecated(underlying, deprecated);
    }

    function testSetIsDeprecatedFailsIfMarketNotCreated(address underlying, bool deprecated) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setIsDeprecated(underlying, deprecated);
    }

    function testSetIsDeprecatedFailsIfBorrowNotPaused(uint256 seed, bool deprecated) public createMarkets {
        address underlying = _randomUnderlying(seed);
        vm.expectRevert(Errors.BorrowNotPaused.selector);
        morpho.setIsDeprecated(underlying, deprecated);
    }

    function testSetIsDeprecated(uint256 seed, bool deprecated) public createMarkets {
        address underlying = _randomUnderlying(seed);
        morpho.setIsBorrowPaused(underlying, true);
        vm.expectEmit(true, true, true, true);
        emit Events.IsDeprecatedSet(underlying, deprecated);
        morpho.setIsDeprecated(underlying, deprecated);
        assertEq(morpho.market(underlying).pauseStatuses.isDeprecated, deprecated);
    }

    function _containsUnderlying(address underlying) internal view returns (bool) {
        for (uint256 i; i < allUnderlyings.length; i++) {
            if (allUnderlyings[i] == underlying) {
                return true;
            }
        }
        return false;
    }
}
