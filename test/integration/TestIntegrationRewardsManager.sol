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

    // From the rewards manager
    event Accrued(
        address indexed asset, address indexed reward, address indexed user, uint256 assetIndex, uint256 rewardsAccrued
    );

    address internal aDai;
    address internal vDai;
    address internal aUsdc;
    address internal vUsdc;

    address[] internal assets;
    RewardsDataTypes.RewardsConfigInput[] rewardsConfig;

    function setUp() public virtual override {
        super.setUp();

        aDai = testMarkets[dai].aToken;
        vDai = testMarkets[dai].variableDebtToken;
        aUsdc = testMarkets[usdc].aToken;
        vUsdc = testMarkets[usdc].variableDebtToken;
        assets = [aDai, vDai, aUsdc, vUsdc];

        ITransferStrategyBase transferStrategy = new PullRewardsTransferStrategyMock();
        deal(wNative, address(transferStrategy), type(uint96).max);
        deal(link, address(transferStrategy), type(uint96).max);

        {
            IEACAggregatorProxy rewardOracle = IEACAggregatorProxy(oracle.getSourceOfAsset(wNative));

            rewardsConfig.push(
                RewardsDataTypes.RewardsConfigInput({
                    emissionPerSecond: 0.001 ether,
                    totalSupply: 0,
                    distributionEnd: 1711944000,
                    asset: aDai,
                    reward: wNative,
                    transferStrategy: transferStrategy,
                    rewardOracle: rewardOracle
                })
            );
            rewardsConfig.push(
                RewardsDataTypes.RewardsConfigInput({
                    emissionPerSecond: 1 ether,
                    totalSupply: 0,
                    distributionEnd: 1711944000,
                    asset: vDai,
                    reward: wNative,
                    transferStrategy: transferStrategy,
                    rewardOracle: rewardOracle
                })
            );
        }

        {
            IEACAggregatorProxy rewardOracle = IEACAggregatorProxy(oracle.getSourceOfAsset(link));

            rewardsConfig.push(
                RewardsDataTypes.RewardsConfigInput({
                    emissionPerSecond: 1 ether,
                    totalSupply: 0,
                    distributionEnd: 1711944000,
                    asset: aUsdc,
                    reward: link,
                    transferStrategy: transferStrategy,
                    rewardOracle: rewardOracle
                })
            );
            rewardsConfig.push(
                RewardsDataTypes.RewardsConfigInput({
                    emissionPerSecond: 1 ether,
                    totalSupply: 0,
                    distributionEnd: 1711944000,
                    asset: vUsdc,
                    reward: link,
                    transferStrategy: transferStrategy,
                    rewardOracle: rewardOracle
                })
            );
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
        blocks = _boundBlocks(blocks);
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
        blocks = _boundBlocks(blocks);
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
        params.blocks = _boundBlocks(params.blocks);

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
        blocks = _boundBlocks(blocks);

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
        blocks = _boundBlocks(blocks);
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
        blocks = _boundBlocks(blocks);

        user.approve(dai, amount);
        user.supply(dai, amount);

        _forward(blocks);

        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));
        uint256 rewardBalanceBefore1 = ERC20(link).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(
            aDai, wNative, address(user), rewardsManager.getAssetIndex(testMarkets[dai].aToken, wNative), accruedRewards
        );
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);

        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 2, "rewardTokens length (1)");
        assertEq(amounts.length, 2, "amounts length (1)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (1)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (1)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0 + accruedRewards, "balance[0] (1)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (1)");
        assertEq(amounts[0], accruedRewards, "amounts[0] (1)");
        assertGt(amounts[0], 0, "amounts[0] > 0 (1)");
        assertEq(amounts[1], 0, "amounts[1] (1)");

        user.withdraw(dai, type(uint256).max);

        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards (2)");
        assertEq(rewardTokens.length, 2, "rewardTokens length (2)");
        assertEq(amounts.length, 2, "amounts length (2)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (2)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (2)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0, "balance[0] (2)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (2)");
        assertEq(amounts[0], 0, "amounts[0] (2)");
        assertEq(amounts[1], 0, "amounts[1] (2)");
    }

    function testClaimRewardsWhenSupplyingCollateral(uint256 amount, uint256 blocks) public {
        amount = _boundSupply(testMarkets[dai], amount);
        blocks = _boundBlocks(blocks);

        user.approve(dai, amount);
        user.supplyCollateral(dai, amount);

        _forward(blocks);

        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));
        uint256 rewardBalanceBefore1 = ERC20(link).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(aDai, wNative, address(user), rewardsManager.getAssetIndex(aDai, wNative), accruedRewards);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);

        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 2, "rewardTokens length (1)");
        assertEq(amounts.length, 2, "amounts length (1)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (1)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (1)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0 + accruedRewards, "balance[0] (1)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (1)");
        assertEq(amounts[0], accruedRewards, "amounts[0] (1)");
        assertGt(amounts[0], 0, "amounts[0] > 0 (1)");
        assertEq(amounts[1], 0, "amounts[1] (1)");

        user.withdrawCollateral(dai, type(uint256).max);

        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards (2)");
        assertEq(rewardTokens.length, 2, "rewardTokens length (2)");
        assertEq(amounts.length, 2, "amounts length (2)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (2)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (2)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0, "balance[0] (2)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (2)");
        assertEq(amounts[0], 0, "amounts[0] (2)");
        assertEq(amounts[1], 0, "amounts[1] (2)");
    }

    function testClaimRewardsWhenBorrowingPool(uint256 amount, uint256 blocks) public {
        amount = _boundBorrow(testMarkets[dai], amount);
        blocks = _boundBlocks(blocks);

        _borrowWithCollateral(
            address(user), testMarkets[wbtc], testMarkets[dai], amount, address(user), address(user), 0
        );

        _forward(blocks);

        uint256 accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        uint256 rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));
        uint256 rewardBalanceBefore1 = ERC20(link).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(vDai, wNative, address(user), rewardsManager.getAssetIndex(vDai, wNative), accruedRewards);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, accruedRewards);

        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 2, "rewardTokens length (1)");
        assertEq(amounts.length, 2, "amounts length (1)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (1)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (1)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0 + accruedRewards, "balance[0] (1)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (1)");
        assertEq(amounts[0], accruedRewards, "amounts[0] (1)");
        assertGt(amounts[0], 0, "amounts[0] > 0 (1)");
        assertEq(amounts[1], 0, "amounts[1] (1)");

        user.approve(dai, type(uint256).max);
        user.repay(dai, type(uint256).max);

        _forward(blocks);

        accruedRewards = rewardsManager.getUserRewards(assets, address(user), wNative);
        rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));

        (rewardTokens, amounts) = morpho.claimRewards(assets, address(user));

        assertEq(accruedRewards, 0, "accruedRewards (2)");
        assertEq(rewardTokens.length, 2, "rewardTokens length (2)");
        assertEq(amounts.length, 2, "amounts length (2)");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0] (2)");
        assertEq(rewardTokens[1], link, "rewardTokens[1] (2)");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0, "balance[0] (2)");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1, "balance[1] (2)");
        assertEq(amounts[0], 0, "amounts[0] (2)");
        assertEq(amounts[1], 0, "amounts[1] (2)");
    }

    function testClaimRewardsWhenSupplyingAndBorrowing(uint256 supplyAmount, uint256 borrowAmount, uint256 blocks)
        public
    {
        supplyAmount = _boundSupply(testMarkets[usdc], supplyAmount);
        borrowAmount = _boundBorrow(testMarkets[dai], borrowAmount);
        blocks = _boundBlocks(blocks);

        user.approve(usdc, supplyAmount);
        user.supply(usdc, supplyAmount);

        _borrowWithoutCollateral(address(user), testMarkets[dai], borrowAmount, address(user), address(user), 0);

        _forward(blocks);

        (address[] memory rewardsList, uint256[] memory unclaimed) =
            rewardsManager.getAllUserRewards(assets, address(user));

        assertEq(rewardsList[0], wNative, "rewardsList[0]");
        assertEq(rewardsList[1], link, "rewardsList[1]");

        uint256 rewardBalanceBefore0 = ERC20(wNative).balanceOf(address(user));
        uint256 rewardBalanceBefore1 = ERC20(link).balanceOf(address(user));

        vm.expectEmit(true, true, true, true);
        emit Accrued(vDai, wNative, address(user), rewardsManager.getAssetIndex(vDai, wNative), unclaimed[0]);
        vm.expectEmit(true, true, true, true);
        emit Accrued(aUsdc, link, address(user), rewardsManager.getAssetIndex(aUsdc, link), unclaimed[1]);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), wNative, unclaimed[0]);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardsClaimed(address(this), address(user), link, unclaimed[1]);
        (address[] memory rewardTokens, uint256[] memory amounts) = morpho.claimRewards(assets, address(user));

        assertEq(rewardTokens.length, 2, "rewardTokens length");
        assertEq(amounts.length, 2, "amounts length");
        assertEq(rewardTokens[0], wNative, "rewardTokens[0]");
        assertEq(rewardTokens[1], link, "rewardTokens[1]");
        assertEq(ERC20(wNative).balanceOf(address(user)), rewardBalanceBefore0 + unclaimed[0], "balance[0]");
        assertEq(ERC20(link).balanceOf(address(user)), rewardBalanceBefore1 + unclaimed[1], "balance[1]");
        assertEq(amounts[0], unclaimed[0], "amounts[0]");
        assertGt(amounts[0], 0, "amounts[0] > 0");
        assertEq(amounts[1], unclaimed[1], "amounts[1]");
        assertGt(amounts[1], 0, "amounts[1] > 0");
    }
}
