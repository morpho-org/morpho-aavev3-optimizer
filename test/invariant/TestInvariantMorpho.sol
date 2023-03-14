// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/InvariantTest.sol";

contract TestInvariantMorpho is InvariantTest {
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using TestMarketLib for TestMarket;

    bytes4[] internal selectors;

    uint256 internal initialized;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        selectors.push(this.supply.selector);
        selectors.push(this.supplyCollateral.selector);
        selectors.push(this.borrow.selector);
        selectors.push(this.repay.selector);
        selectors.push(this.withdraw.selector);
        selectors.push(this.withdrawCollateral.selector);
        selectors.push(this.liquidate.selector);
        selectors.push(this.initialize.selector);
        selectors.push(this.approveManager.selector);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function initialize(
        address addressesProvider,
        uint8 eModeCategoryId,
        address newPositionsManager,
        Types.Iterations memory newDefaultIterations
    ) external {
        vm.prank(msg.sender);
        try morpho.initialize(addressesProvider, eModeCategoryId, newPositionsManager, newDefaultIterations) {
            ++initialized;
        } catch {}
    }

    function supply(uint256 underlyingSeed, uint256 amount, address onBehalf, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundSupply(market, amount);
        onBehalf = _randomSender(onBehalf);
        maxIterations = _boundMaxIterations(maxIterations);

        _deal(market.underlying, msg.sender, amount);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.supply(market.underlying, amount, onBehalf, maxIterations);
        vm.stopPrank();
    }

    function supplyCollateral(uint256 underlyingSeed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundSupply(market, amount);
        onBehalf = _randomSender(onBehalf);

        _deal(market.underlying, msg.sender, amount);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.supplyCollateral(market.underlying, amount, onBehalf);
        vm.stopPrank();
    }

    function borrow(uint256 underlyingSeed, uint256 amount, address onBehalf, address receiver, uint256 maxIterations)
        external
    {
        TestMarket storage market = testMarkets[_randomBorrowable(underlyingSeed)];
        amount = _boundBorrow(market, amount);
        onBehalf = _randomSender(onBehalf);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        vm.prank(msg.sender);
        morpho.borrow(market.underlying, amount, onBehalf, receiver, maxIterations);
    }

    function repay(uint256 underlyingSeed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomBorrowable(underlyingSeed)];
        amount = _boundNotZero(amount);
        onBehalf = _randomSender(onBehalf);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.repay(market.underlying, amount, onBehalf);
        vm.stopPrank();
    }

    function withdraw(uint256 underlyingSeed, uint256 amount, address onBehalf, address receiver, uint256 maxIterations)
        external
    {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundNotZero(amount);
        onBehalf = _randomSender(onBehalf);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        vm.prank(msg.sender);
        morpho.withdraw(market.underlying, amount, onBehalf, receiver, maxIterations);
    }

    function withdrawCollateral(uint256 underlyingSeed, uint256 amount, address onBehalf, address receiver) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundNotZero(amount);
        onBehalf = _randomSender(onBehalf);
        receiver = _boundReceiver(receiver);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market.underlying, amount, onBehalf, receiver);
    }

    function liquidate(uint256 underlyingBorrowed, uint256 underlyingCollateral, address liquidatee, uint256 amount)
        external
    {
        TestMarket storage borrowedMarket = testMarkets[_randomUnderlying(underlyingBorrowed)];
        TestMarket storage collateralMarket = testMarkets[_randomUnderlying(underlyingCollateral)];
        liquidatee = _randomSender(liquidatee);

        vm.prank(msg.sender);
        morpho.liquidate(borrowedMarket.underlying, collateralMarket.underlying, liquidatee, amount);
    }

    function approveManager(address manager, bool isAllowed) external {
        manager = _randomSender(manager);

        vm.prank(msg.sender);
        morpho.approveManager(manager, isAllowed);
    }

    function invariantInitialized() public {
        assertEq(initialized, 0, "initialized");
    }

    function invariantBalanceOf() public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            ERC20 underlying = ERC20(allUnderlyings[i]);

            assertEq(underlying.balanceOf(address(morpho)), 0, string.concat(underlying.symbol(), ".balanceOf"));
        }
    }

    function invariantHealthFactor() public {
        (,,,,, uint256 healthFactor) = pool.getUserAccountData(address(morpho));

        assertGt(healthFactor, Constants.DEFAULT_LIQUIDATION_MAX_HF, "healthFactor");
    }

    function invariantCannotBorrowOverLtv() public {
        address[] memory senders = targetSenders();

        for (uint256 i; i < senders.length; ++i) {
            address sender = senders[i];
            Types.LiquidityData memory liquidityData = morpho.liquidityData(sender);

            if (liquidityData.borrowable == 0) continue;

            for (uint256 j; j < borrowableUnderlyings.length; ++j) {
                TestMarket storage market = testMarkets[borrowableUnderlyings[j]];

                uint256 borrowable = (liquidityData.borrowable * 1 ether * 10 ** market.decimals).percentAdd(5) // Inflate borrowable because of WBTC decimals precision.
                    / (market.price * 1 ether);
                if (borrowable == 0 || borrowable > market.liquidity()) continue;

                vm.prank(sender);
                vm.expectRevert(Errors.UnauthorizedBorrow.selector);
                morpho.borrow(market.underlying, borrowable, sender, sender, 0);
            }
        }
    }

    function invariantCannotWithdrawOverLt() public {
        address[] memory senders = targetSenders();

        for (uint256 i; i < senders.length; ++i) {
            address sender = senders[i];
            address[] memory collaterals = morpho.userCollaterals(sender);
            Types.LiquidityData memory liquidityData = morpho.liquidityData(sender);

            if (liquidityData.debt == 0) continue;

            for (uint256 j; j < collaterals.length; ++j) {
                TestMarket storage market = testMarkets[collaterals[j]];

                // TODO: replace with .getLt() & use rawCollateralValue()
                uint256 withdrawable = (
                    ((liquidityData.maxDebt - liquidityData.debt) * 1 ether * 10 ** market.decimals).percentAdd(5)
                        / (market.price * 1 ether)
                ) // Inflate withdrawable because of WBTC decimals precision.
                    .percentDiv(market.lt) * Constants.LT_LOWER_BOUND / (Constants.LT_LOWER_BOUND - 1);
                if (withdrawable == 0) continue;

                vm.prank(sender);
                vm.expectRevert(Errors.UnauthorizedWithdraw.selector);
                morpho.withdrawCollateral(market.underlying, withdrawable, sender, sender);
            }
        }
    }
}
