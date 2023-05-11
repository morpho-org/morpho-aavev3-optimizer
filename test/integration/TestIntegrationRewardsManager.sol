// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IScaledBalanceToken} from "@aave-v3-core/interfaces/IScaledBalanceToken.sol";
import {IEACAggregatorProxy} from "@aave-v3-periphery/misc/interfaces/IEACAggregatorProxy.sol";
import {ITransferStrategyBase} from "@aave-v3-periphery/rewards/interfaces/ITransferStrategyBase.sol";

import {RewardsDataTypes} from "@aave-v3-periphery/rewards/libraries/RewardsDataTypes.sol";

import {PullRewardsTransferStrategyMock} from "test/mocks/PullRewardsTransferStrategyMock.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationRewardsManager is IntegrationTest {
    using ConfigLib for Config;

    uint256 internal constant MAX_BLOCKS = 100_000;

    // From the rewards manager
    event Accrued(
        address indexed asset, address indexed reward, address indexed user, uint256 assetIndex, uint256 rewardsAccrued
    );

    address[] internal assets;
    address internal aDai;
    address internal vDai;
    address internal aUsdc;
    address internal vUsdc;

    function setUp() public virtual override {
        super.setUp();

        aDai = testMarkets[dai].aToken;
        vDai = testMarkets[dai].variableDebtToken;
        aUsdc = testMarkets[usdc].aToken;
        vUsdc = testMarkets[usdc].variableDebtToken;
        assets = [aDai, vDai, aUsdc, vUsdc];

        ITransferStrategyBase transferStrategy = new PullRewardsTransferStrategyMock();
        deal(wNative, address(transferStrategy), type(uint256).max);

        IEACAggregatorProxy rewardOracle = IEACAggregatorProxy(oracle.getSourceOfAsset(wNative));

        RewardsDataTypes.RewardsConfigInput[] memory rewardsConfig =
            new RewardsDataTypes.RewardsConfigInput[](assets.length);

        for (uint256 i; i < assets.length; ++i) {
            rewardsConfig[i] = RewardsDataTypes.RewardsConfigInput({
                emissionPerSecond: 1 ether,
                totalSupply: 0,
                distributionEnd: 1711944000,
                asset: assets[i],
                reward: wNative,
                transferStrategy: transferStrategy,
                rewardOracle: rewardOracle
            });
        }

        vm.prank(emissionManager);
        rewardsController.configureAssets(rewardsConfig);
    }

    function testGetMorpho() public {
        assertEq(rewardsManager.MORPHO(), address(morpho));
    }

    function testGetRewardsController() public {
        assertEq(rewardsManager.REWARDS_CONTROLLER(), address(rewardsController));
    }

    function testGetRewardData(uint256 amount, uint256 blocks) public {
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = bound(blocks, 0, MAX_BLOCKS);
        (uint256 startingIndex, uint256 index, uint256 lastUpdateTimestamp) =
            rewardsManager.getRewardData(aDai, wNative);

        assertEq(startingIndex, 0, "starting index before");
        assertEq(index, 0, "index before");
        assertEq(lastUpdateTimestamp, 0, "lastUpdateTimestamp before");

        user.approve(dai, amount);
        user.supply(dai, amount);

        uint256 expectedIndex = rewardsManager.getAssetIndex(aDai, wNative);
        uint256 expectedTimestamp = block.timestamp;

        (startingIndex, index, lastUpdateTimestamp) = rewardsManager.getRewardData(aDai, wNative);
        assertEq(startingIndex, expectedIndex, "starting index after supply");
        assertEq(index, expectedIndex, "index after supply");
        assertEq(lastUpdateTimestamp, expectedTimestamp, "lastUpdateTimestamp after supply");

        _forward(blocks);

        (startingIndex, index, lastUpdateTimestamp) = rewardsManager.getRewardData(aDai, wNative);
        assertEq(startingIndex, expectedIndex, "starting index after forward");
        assertEq(index, expectedIndex, "index after forward");
        assertEq(lastUpdateTimestamp, expectedTimestamp, "lastUpdateTimestamp after forward");
    }

    function testGetUserData(uint256 amount, uint256 blocks) public {
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        (uint256 index, uint256 accrued) = rewardsManager.getUserData(aDai, wNative, address(user));

        assertEq(index, 0, "index before");
        assertEq(accrued, 0, "accrued before");

        user.approve(dai, amount);
        user.supply(dai, amount);

        (index, accrued) = rewardsManager.getUserData(aDai, wNative, address(user));

        // The user's first index is expected to be zero because on the first reward update,
        // the update is bypassed as the reward starting index is set to what the user's asset index would be.
        assertEq(index, 0, "index after supply");
        assertEq(accrued, 0, "accrued after supply");

        _forward(blocks);

        user.approve(dai, amount);
        user.supply(dai, amount);

        uint256 expectedIndex = rewardsManager.getAssetIndex(aDai, wNative);
        uint256 expectedAccrued = rewardsManager.getUserRewards(assets, address(user), wNative);

        (index, accrued) = rewardsManager.getUserData(aDai, wNative, address(user));

        assertEq(index, expectedIndex, "index after forward");
        assertEq(accrued, expectedAccrued, "accrued after forward");

        user.withdraw(dai, type(uint256).max);

        expectedIndex = rewardsManager.getAssetIndex(aDai, wNative);
        expectedAccrued = rewardsManager.getUserRewards(assets, address(user), wNative);

        (index, accrued) = rewardsManager.getUserData(aDai, wNative, address(user));

        assertEq(index, expectedIndex, "index after withdraw");
        assertEq(accrued, expectedAccrued, "accrued after withdraw");
    }

    // TODO: Figure out how to have multiple reward tokens for testing this.
    // function testGetAllUserRewards() public {}

    struct RewardTest {
        uint256 collateralDai;
        uint256 collateralUsdc;
        uint256 supplyDai;
        uint256 supplyUsdc;
        uint256 borrowDai;
        uint256 blocks;
    }

    function testGetUserRewards(RewardTest memory params) public {
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

        uint256 expectedAccrued = _calculateRewardByAsset(address(user), scaledCollateralDai, aDai, wNative);
        expectedAccrued += _calculateRewardByAsset(address(user), scaledSupplyDai, aDai, wNative);
        expectedAccrued += _calculateRewardByAsset(address(user), scaledBorrowDai, vDai, wNative);
        expectedAccrued += _calculateRewardByAsset(address(user), scaledCollateralUsdc, aUsdc, wNative);
        expectedAccrued += _calculateRewardByAsset(address(user), scaledSupplyUsdc, aUsdc, wNative);

        accrued = rewardsManager.getUserRewards(assets, address(user), wNative);

        assertApproxEqAbs(accrued, expectedAccrued, 5, "accrued 2");
    }

    function _calculateRewardByAsset(address user, uint256 scaledBalance, address asset, address reward)
        internal
        view
        returns (uint256)
    {
        uint256 assetUnit = 10 ** rewardsController.getAssetDecimals(asset);
        uint256 userIndex = rewardsManager.getUserAssetIndex(user, asset, reward);
        uint256 assetIndex = rewardsManager.getAssetIndex(asset, reward);

        return scaledBalance * (assetIndex - userIndex) / assetUnit;
    }

    function testGetUserAssetIndex(uint256 amount, uint256 blocks) public {
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = bound(blocks, 0, MAX_BLOCKS);

        uint256 startingAssetIndex = rewardsManager.getAssetIndex(aDai, wNative);

        // The case where rewards manager has never been updated.
        uint256 index = rewardsManager.getUserAssetIndex(address(user), aDai, wNative);
        assertEq(index, 0, "index 1");

        // The case where the rewards manager has been updated and the user's asset index has not.
        user.approve(dai, amount);
        user.supplyCollateral(dai, amount);
        index = rewardsManager.getUserAssetIndex(address(user), aDai, wNative);
        assertEq(index, startingAssetIndex, "index 2");

        _forward(blocks);

        // The user asset index should be the same in future blocks without an update call.
        index = rewardsManager.getUserAssetIndex(address(user), aDai, wNative);
        assertEq(index, startingAssetIndex, "index 3");

        // After an update call, the user's asset index should be updated to the current asset index.
        user.approve(dai, amount);
        user.supplyCollateral(dai, amount);

        index = rewardsManager.getUserAssetIndex(address(user), aDai, wNative);
        assertEq(index, rewardsManager.getAssetIndex(aDai, wNative), "index 4");
    }

    function testGetAssetIndex(uint256 blocks) public {
        blocks = bound(blocks, 1, MAX_BLOCKS);
        uint256 assetUnit = 10 ** rewardsController.getAssetDecimals(aDai);
        uint256 currentTimestamp = block.timestamp;

        (uint256 rewardIndex, uint256 emissionPerSecond, uint256 lastUpdateTimestamp, uint256 distributionEnd) =
            rewardsController.getRewardsData(aDai, wNative);
        uint256 totalEmitted = emissionPerSecond * (currentTimestamp - lastUpdateTimestamp) * assetUnit
            / IScaledBalanceToken(aDai).scaledTotalSupply();

        assertEq(rewardsManager.getAssetIndex(aDai, wNative), rewardIndex + totalEmitted, "index 1");

        _forward(blocks);

        currentTimestamp = block.timestamp;

        currentTimestamp = currentTimestamp > distributionEnd ? distributionEnd : currentTimestamp;
        totalEmitted = emissionPerSecond * (currentTimestamp - lastUpdateTimestamp) * assetUnit
            / IScaledBalanceToken(aDai).scaledTotalSupply();

        assertEq(rewardsManager.getAssetIndex(aDai, wNative), rewardIndex + totalEmitted, "index 2");
    }

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
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        user.approve(dai, amount);
        user.supply(dai, amount);
        _forward(blocks);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(
            aDai, wNative, address(user), rewardsManager.getAssetIndex(testMarkets[dai].aToken, wNative), accruedRewards
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
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        user.approve(dai, amount);
        user.supplyCollateral(dai, amount);
        _forward(blocks);
        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(aDai, wNative, address(user), rewardsManager.getAssetIndex(aDai, wNative), accruedRewards);
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
        amount = _boundBorrow(testMarkets[dai], amount);
        blocks = bound(blocks, 1, MAX_BLOCKS);
        _borrowWithCollateral(
            address(user), testMarkets[wbtc], testMarkets[dai], amount, address(user), address(user), 0
        );

        _forward(blocks);

        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(vDai, wNative, address(user), rewardsManager.getAssetIndex(vDai, wNative), accruedRewards);
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

    function testClaimRewardsWhenSupplyingAndBorrowing(uint256 supplyAmount, uint256 borrowAmount, uint256 blocks)
        public
    {
        supplyAmount = _boundSupply(testMarkets[dai], supplyAmount);
        borrowAmount = _boundBorrow(testMarkets[dai], borrowAmount);
        blocks = bound(blocks, 1, MAX_BLOCKS);

        user.approve(dai, supplyAmount);
        user.supplyCollateral(dai, supplyAmount);

        _borrowWithoutCollateral(address(user), testMarkets[dai], borrowAmount, address(user), address(user), 0);

        _forward(blocks);

        address[] memory aDaiArray = new address[](1);
        aDaiArray[0] = aDai;
        address[] memory vDaiArray = new address[](1);
        vDaiArray[0] = vDai;

        uint256 accruedRewardCollateral = rewardsManager.getUserRewards(aDaiArray, address(user), wNative);
        uint256 accruedRewardBorrow = rewardsManager.getUserRewards(vDaiArray, address(user), wNative);
        uint256 rewardBalanceBefore = ERC20(wNative).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(aDai, wNative, address(user), rewardsManager.getAssetIndex(aDai, wNative), accruedRewardCollateral);
        vm.expectEmit(true, true, true, true);
        emit Accrued(vDai, wNative, address(user), rewardsManager.getAssetIndex(vDai, wNative), accruedRewardBorrow);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewardCollateral + accruedRewardBorrow);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 1, "rewardTokens length 1");
        assertEq(amounts.length, 1, "amounts length 1");
        assertEq(rewardTokens[0], wNative, "rewardTokens 1");
        assertEq(
            ERC20(wNative).balanceOf(address(user)),
            rewardBalanceBefore + accruedRewardCollateral + accruedRewardBorrow,
            "balance 1"
        );
        assertEq(amounts[0], accruedRewardCollateral + accruedRewardBorrow, "amount 1");
        assertGt(amounts[0], 0, "amount min 1");
    }
}
