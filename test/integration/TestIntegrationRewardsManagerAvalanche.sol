// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRewardsManagerAvalanche is IntegrationTest {
    using TestConfigLib for TestConfig;

    uint256 internal constant MIN_AMOUNT = 1 ether;
    uint256 internal constant MAX_AMOUNT = 1_000_000 ether; // Only ~$2m of borrow liquidity of DAI in avalanche
    uint256 internal constant MAX_BLOCKS = 100_000;

    // From the rewards manager
    event Accrued(
        address indexed asset, address indexed reward, address indexed user, uint256 assetIndex, uint256 rewardsAccrued
    );

    address[] internal assets;
    address internal aTokenDai;
    address internal variableDebtTokenDai;
    address internal aTokenUsdc;
    address internal variableDebtTokenUsdc;

    function setUp() public virtual override {
        super.setUp();
        rewardsController = IRewardsController(config.getRewardsController());
        rewardsManager = IRewardsManager(new RewardsManager(address(rewardsController), address(morpho)));
        morpho.setRewardsManager(address(rewardsManager));
        aTokenDai = testMarkets[dai].aToken;
        variableDebtTokenDai = testMarkets[dai].variableDebtToken;
        aTokenUsdc = testMarkets[usdc].aToken;
        variableDebtTokenUsdc = testMarkets[usdc].variableDebtToken;
        assets = [aTokenDai, variableDebtTokenDai, aTokenUsdc, variableDebtTokenUsdc];
    }

    /// @dev We can only use avalanche mainnet because mainnet doesn't have a rewards controller yet
    function _network() internal view virtual override returns (string memory) {
        return "avalanche-mainnet";
    }

    function testGetMorpho() public {
        assertEq(rewardsManager.MORPHO(), address(morpho));
    }

    function testGetRewardsController() public {
        assertEq(rewardsManager.REWARDS_CONTROLLER(), address(rewardsController));
    }

    function testGetRewardData(uint256 amount, uint256 blocks) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        blocks = bound(blocks, 0, MAX_BLOCKS);
        (uint256 index, uint256 lastUpdateTimestamp) = rewardsManager.getRewardData(aTokenDai, wNative);

        assertEq(index, 0, "index before");
        assertEq(lastUpdateTimestamp, 0, "lastUpdateTimestamp before");

        user.approve(dai, amount);
        user.supply(dai, amount);

        uint256 expectedIndex = rewardsManager.getAssetIndex(aTokenDai, wNative);
        uint256 expectedTimestamp = block.timestamp;

        (index, lastUpdateTimestamp) = rewardsManager.getRewardData(aTokenDai, wNative);
        assertEq(index, expectedIndex, "index after supply");
        assertEq(lastUpdateTimestamp, expectedTimestamp, "lastUpdateTimestamp after supply");

        _forward(blocks);

        (index, lastUpdateTimestamp) = rewardsManager.getRewardData(aTokenDai, wNative);
        assertEq(index, expectedIndex, "index after forward");
        assertEq(lastUpdateTimestamp, expectedTimestamp, "lastUpdateTimestamp after forward");
    }

    function testGetUserData(uint256 amount, uint256 blocks) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        (uint256 index, uint256 accrued) = rewardsManager.getUserData(aTokenDai, wNative, address(user));

        assertEq(index, 0, "index before");
        assertEq(accrued, 0, "accrued before");

        user.approve(dai, amount);
        user.supply(dai, amount);

        (index, accrued) = rewardsManager.getUserData(aTokenDai, wNative, address(user));

        // The user's first index is expected to be zero because on the first reward update, the update is bypassed as the reward starting index is set to zero.
        assertEq(index, 0, "index after supply");
        assertEq(accrued, 0, "accrued after supply");

        _forward(blocks);

        user.approve(dai, amount);
        user.supply(dai, amount);

        uint256 expectedIndex = rewardsManager.getAssetIndex(aTokenDai, wNative);
        uint256 expectedAccrued = rewardsManager.getUserRewards(assets, address(user), wNative);

        (index, accrued) = rewardsManager.getUserData(aTokenDai, wNative, address(user));

        assertEq(index, expectedIndex, "index after forward");
        assertEq(accrued, expectedAccrued, "accrued after forward");

        user.withdraw(dai, type(uint256).max);

        expectedIndex = rewardsManager.getAssetIndex(aTokenDai, wNative);
        expectedAccrued = rewardsManager.getUserRewards(assets, address(user), wNative);

        (index, accrued) = rewardsManager.getUserData(aTokenDai, wNative, address(user));

        assertEq(index, expectedIndex, "index after withdraw");
        assertEq(accrued, expectedAccrued, "accrued after withdraw");
    }

    // TODO: Figure out how to have multiple reward tokens for testing this.
    // function testGetAllUserRewards() public {}

    struct TestRewardStruct {
        uint256 collateralDai;
        uint256 collateralUsdc;
        uint256 supplyDai;
        uint256 supplyUsdc;
        uint256 borrowDai;
        uint256 blocks;
    }

    function testGetUserRewards(TestRewardStruct memory params) public {
        params.collateralDai = _boundSupply(testMarkets[dai], params.collateralDai);
        params.collateralUsdc = _boundSupply(testMarkets[usdc], params.collateralUsdc);
        params.supplyDai = _boundSupply(testMarkets[dai], params.supplyDai);
        params.supplyUsdc = _boundSupply(testMarkets[usdc], params.supplyUsdc);
        params.borrowDai = _boundBorrow(testMarkets[dai], params.borrowDai);
        params.blocks = bound(params.blocks, 0, MAX_BLOCKS);

        // Initialize asset indexes for each asset
        hacker.approve(dai, 1000);
        hacker.supplyCollateral(dai, 1000);
        hacker.approve(usdc, 1000);
        hacker.supplyCollateral(usdc, 1000);
        hacker.borrow(dai, 100);
        hacker.borrow(usdc, 100);

        _forward(1);

        user.approve(dai, params.collateralDai);
        user.supplyCollateral(dai, params.collateralDai);
        user.approve(usdc, params.collateralUsdc);
        user.supplyCollateral(usdc, params.collateralUsdc);
        user.approve(dai, params.supplyDai);
        user.supply(dai, params.supplyDai);
        user.approve(usdc, params.supplyUsdc);
        user.supply(usdc, params.supplyUsdc);
        _borrowWithoutCollateral(address(user), testMarkets[dai], params.borrowDai, address(user), address(user), 0);

        uint256 scaledCollateralDai = morpho.scaledCollateralBalance(dai, address(user));
        uint256 scaledCollateralUsdc = morpho.scaledCollateralBalance(usdc, address(user));
        uint256 scaledSupplyDai = morpho.scaledPoolSupplyBalance(dai, address(user));
        uint256 scaledSupplyUsdc = morpho.scaledPoolSupplyBalance(usdc, address(user));
        uint256 scaledBorrowDai = morpho.scaledPoolBorrowBalance(dai, address(user));

        (uint256 accrued) = rewardsManager.getUserRewards(assets, address(user), wNative);
        assertEq(accrued, 0, "accrued 1");

        _forward(params.blocks);

        uint256[] memory assetIndexes = new uint256[](assets.length);
        uint256[] memory userIndexes = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            assetIndexes[i] = rewardsManager.getAssetIndex(assets[i], wNative);
            userIndexes[i] = rewardsManager.getUserAssetIndex(address(user), assets[i], wNative);
        }

        (accrued) = rewardsManager.getUserRewards(assets, address(user), wNative);
        // TODO: Make this test more accurate with math from previous variables.
        assertGe(accrued, 0, "accrued 2");
    }

    function testGetUserAssetIndex() public {}

    function testGetAssetIndex() public {}

    function testClaimRewardsRevertIfPaused() public {
        morpho.setIsClaimRewardsPaused(true);

        vm.expectRevert(Errors.ClaimRewardsPaused.selector);
        morpho.claimRewards(assets, address(this));
    }

    function testClaimRewardsRevertIfRewardsManagerZero() public {
        morpho.setRewardsManager(address(0));

        vm.expectRevert(Errors.AddressIsZero.selector);
        morpho.claimRewards(assets, address(this));
    }

    function testClaimRewardsWhenSupplyingPool(uint256 amount, uint256 blocks) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        user.approve(dai, amount);
        user.supply(dai, amount);
        _forward(blocks);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(
            aTokenDai,
            wNative,
            address(user),
            rewardsManager.getAssetIndex(testMarkets[dai].aToken, wNative),
            accruedRewards
        );
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);

        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1, "rewardTokens length 1");
        assertEq(amounts.length, 1, "amounts length 1");
        assertEq(rewardTokens[0], wNative, "rewardTokens 1");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore + accruedRewards, "balance 1");
        assertEq(amounts[0], accruedRewards, "amount 1");
        assertGt(amounts[0], 0, "amount min 1");

        user.withdraw(dai, type(uint256).max);
        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards");
        assertEq(rewardTokens.length, 1, "rewardTokens length 2");
        assertEq(amounts.length, 1, "amounts length 2");
        assertEq(rewardTokens[0], wNative, "rewardTokens 2");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore, "balance 2");
        assertEq(amounts[0], 0, "amount 2");
    }

    function testClaimRewardsWhenSupplyingCollateral(uint256 amount, uint256 blocks) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        user.approve(dai, amount);
        user.supplyCollateral(dai, amount);
        _forward(blocks);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(
            aTokenDai, wNative, address(user), rewardsManager.getAssetIndex(aTokenDai, wNative), accruedRewards
        );
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);

        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1, "rewardTokens length 1");
        assertEq(amounts.length, 1, "amounts length 1");
        assertEq(rewardTokens[0], wNative, "rewardTokens 1");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore + accruedRewards, "balance 1");
        assertEq(amounts[0], accruedRewards, "amount 1");
        assertGt(amounts[0], 0, "amount min 1");

        user.withdrawCollateral(dai, type(uint256).max);
        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards");
        assertEq(rewardTokens.length, 1, "rewardTokens length 2");
        assertEq(amounts.length, 1, "amounts length 2");
        assertEq(rewardTokens[0], wNative, "rewardTokens 2");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore, "balance 2");
        assertEq(amounts[0], 0, "amount 2");
    }

    function testClaimRewardsWhenBorrowingPool(uint256 amount, uint256 blocks) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        _borrowWithCollateral(
            address(user), testMarkets[wbtc], testMarkets[dai], amount, address(user), address(user), 0
        );

        _forward(blocks);

        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(
            variableDebtTokenDai,
            wNative,
            address(user),
            rewardsManager.getAssetIndex(testMarkets[dai].variableDebtToken, wNative),
            accruedRewards
        );
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1, "rewardTokens length 1");
        assertEq(amounts.length, 1, "amounts length 1");
        assertEq(rewardTokens[0], wNative, "rewardTokens 1");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore + accruedRewards, "balance 1");
        assertEq(amounts[0], accruedRewards, "amount 1");
        assertGt(amounts[0], 0, "amount min 1");

        user.approve(dai, type(uint256).max);
        user.repay(dai, type(uint256).max);

        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards");
        assertEq(rewardTokens.length, 1, "rewardTokens length 2");
        assertEq(amounts.length, 1, "amounts length 2");
        assertEq(rewardTokens[0], wNative, "rewardTokens 2");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore, "balance 2");
        assertEq(amounts[0], 0, "amount 2");
    }
}
