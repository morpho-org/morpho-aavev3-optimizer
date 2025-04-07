// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/InvariantTest.sol";

contract TestInvariantAccessControl is InvariantTest {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using TestMarketLib for TestMarket;

    uint256 internal initialized;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _weightSelector(this.initialize.selector, 5);
        _weightSelector(this.supply.selector, 10);
        _weightSelector(this.supplyCollateral.selector, 15);
        _weightSelector(this.borrow.selector, 15);
        _weightSelector(this.repay.selector, 10);
        _weightSelector(this.withdraw.selector, 10);
        _weightSelector(this.withdrawCollateral.selector, 15);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    /* FUNCTIONS */

    function initialize(
        address addressesProvider,
        uint8 eModeCategoryId,
        address newPositionsManager,
        Types.Iterations memory newDefaultIterations
    ) external {
        vm.prank(msg.sender);
        try morpho.initialize(addressesProvider, eModeCategoryId, newPositionsManager, newDefaultIterations) {
            ++initialized;
        } catch (bytes memory reason) {
            revert(string(reason)); // Bubble up the revert reason.
        }
    }

    function supply(uint256 underlyingSeed, uint256 amount, address onBehalf, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundSupply(market, amount);
        onBehalf = _randomSender(onBehalf);
        maxIterations = _boundMaxIterations(maxIterations);

        deal(market.underlying, msg.sender, amount);

        vm.prank(msg.sender); // Cannot startPrank because `morpho.supply` may revert and not call stopPrank.
        ERC20(market.underlying).safeApprove(address(morpho), amount);

        vm.prank(msg.sender);
        morpho.supply(market.underlying, amount, onBehalf, maxIterations);
    }

    function supplyCollateral(uint256 underlyingSeed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundSupply(market, amount);

        deal(market.underlying, msg.sender, amount);

        vm.prank(msg.sender); // Cannot startPrank because `morpho.supplyCollateral` may revert and not call stopPrank.
        ERC20(market.underlying).safeApprove(address(morpho), amount);

        vm.prank(msg.sender);
        morpho.supplyCollateral(market.underlying, amount, onBehalf);
    }

    function borrow(uint256 underlyingSeed, uint256 amount, address receiver, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomBorrowableInEMode(underlyingSeed)];
        amount = _boundBorrow(market, amount);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        _borrowWithoutCollateral(msg.sender, market, amount, msg.sender, receiver, maxIterations);
    }

    function repay(uint256 underlyingSeed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomBorrowableInEMode(underlyingSeed)];
        amount = _boundNotZero(amount);
        onBehalf = _randomSender(onBehalf);

        vm.prank(msg.sender); // Cannot startPrank because `morpho.repay` may revert and not call stopPrank.
        ERC20(market.underlying).safeApprove(address(morpho), amount);

        vm.prank(msg.sender);
        morpho.repay(market.underlying, amount, onBehalf);
    }

    function withdraw(uint256 underlyingSeed, uint256 amount, address receiver, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundNotZero(amount);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        vm.prank(msg.sender);
        morpho.withdraw(market.underlying, amount, msg.sender, receiver, maxIterations);
    }

    function withdrawCollateral(uint256 underlyingSeed, uint256 amount, address receiver) external {
        TestMarket storage market = testMarkets[_randomUnderlying(underlyingSeed)];
        amount = _boundNotZero(amount);
        receiver = _boundReceiver(receiver);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market.underlying, amount, msg.sender, receiver);
    }

    /* INVARIANTS */

    function invariantInitialized() public view {
        assertEq(initialized, 0, "initialized");
    }

    function invariantCannotBorrowOverLtv() public {
        address[] memory senders = targetSenders();

        for (uint256 i; i < senders.length; ++i) {
            address sender = senders[i];
            Types.LiquidityData memory liquidityData = morpho.liquidityData(sender);

            if (liquidityData.borrowable == 0) continue;

            for (uint256 j; j < borrowableInEModeUnderlyings.length; ++j) {
                TestMarket storage market = testMarkets[borrowableInEModeUnderlyings[j]];

                // Inflate borrowable because of WBTC decimals precision.
                uint256 borrowableInUnderlying =
                    (liquidityData.borrowable * 10 ** market.decimals).divUp(market.price).percentAdd(10);
                if (borrowableInUnderlying == 0 || borrowableInUnderlying > market.liquidity()) continue;

                vm.prank(sender);
                vm.expectRevert(Errors.UnauthorizedBorrow.selector);
                morpho.borrow(market.underlying, borrowableInUnderlying, sender, sender, 0);
            }
        }
    }

    function testWithdrawCollateralSimple() public {
        address sender = 0x0000001000000000000000000000000000000000;
        bool success;
        vm.prank(sender);
        (success,) = address(this).call(abi.encodeWithSelector(this.supplyCollateral.selector, 1, 1000145, sender));
        require(success);
        vm.prank(sender);
        (success,) = address(this).call(abi.encodeWithSelector(this.supplyCollateral.selector, 4, 3722, sender));
        require(success);
        vm.prank(sender);
        (success,) =
            address(this).call(abi.encodeWithSelector(this.borrow.selector, 7, 1224089561356568, address(2), 9));
        require(success);
        address[] memory collaterals = morpho.userCollaterals(sender);
        Types.LiquidityData memory liquidityData = morpho.liquidityData(sender);
        require(liquidityData.debt != 0, "no debt");

        TestMarket storage market = testMarkets[collaterals[1]];

        console.log(uint256(1300137100000000000000000000000000).percentAdd(32));
        console.log(market.price * 1 ether);
        console.log(market.getLt(eModeCategoryId));

        uint256 withdrawable = rawCollateralValue(
            (
                ((liquidityData.maxDebt.zeroFloorSub(liquidityData.debt)) * 1 ether * 10 ** market.decimals).percentAdd(
                    32
                ) / (market.price * 1 ether)
            ).percentDiv(market.getLt(eModeCategoryId))
        );
        console.log("withdrawab", withdrawable);
        require(
            !(withdrawable == 0 || withdrawable > morpho.collateralBalance(market.underlying, sender)),
            "no withdrawable"
        );

        vm.prank(sender);
        vm.expectRevert(Errors.UnauthorizedWithdraw.selector);
        morpho.withdrawCollateral(market.underlying, withdrawable, sender, sender);
    }
}
