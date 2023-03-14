// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/InvariantTest.sol";

contract TestInvariantMorpho is InvariantTest {
    using SafeTransferLib for ERC20;

    function setUp() public virtual override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = this.supply.selector;
        selectors[1] = this.supplyCollateral.selector;
        selectors[2] = this.borrow.selector;
        selectors[3] = this.repay.selector;
        selectors[4] = this.withdraw.selector;
        selectors[5] = this.withdrawCollateral.selector;

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function supply(uint256 seed, uint256 amount, address onBehalf, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        amount = _boundSupply(market, amount);
        onBehalf = _boundAddressNotZero(onBehalf);
        maxIterations = _boundMaxIterations(maxIterations);

        _deal(market.underlying, msg.sender, amount);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.supply(market.underlying, amount, onBehalf, maxIterations);
        vm.stopPrank();
    }

    function supplyCollateral(uint256 seed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        amount = _boundSupply(market, amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        _deal(market.underlying, msg.sender, amount);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.supplyCollateral(market.underlying, amount, onBehalf);
        vm.stopPrank();
    }

    function borrow(uint256 seed, uint256 amount, address onBehalf, address receiver, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomBorrowable(seed)];
        amount = _boundBorrow(market, amount);
        onBehalf = _boundAddressNotZero(onBehalf);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        vm.prank(msg.sender);
        morpho.borrow(market.underlying, amount, onBehalf, receiver, maxIterations);
    }

    function repay(uint256 seed, uint256 amount, address onBehalf) external {
        TestMarket storage market = testMarkets[_randomBorrowable(seed)];
        amount = _boundNotZero(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.startPrank(msg.sender);
        ERC20(market.underlying).safeApprove(address(morpho), amount);
        morpho.repay(market.underlying, amount, onBehalf);
        vm.stopPrank();
    }

    function withdraw(uint256 seed, uint256 amount, address onBehalf, address receiver, uint256 maxIterations)
        external
    {
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        amount = _boundNotZero(amount);
        onBehalf = _boundAddressNotZero(onBehalf);
        receiver = _boundReceiver(receiver);
        maxIterations = _boundMaxIterations(maxIterations);

        vm.prank(msg.sender);
        morpho.withdraw(market.underlying, amount, onBehalf, receiver, maxIterations);
    }

    function withdrawCollateral(uint256 seed, uint256 amount, address onBehalf, address receiver) external {
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        amount = _boundNotZero(amount);
        onBehalf = _boundAddressNotZero(onBehalf);
        receiver = _boundReceiver(receiver);

        vm.prank(msg.sender);
        morpho.withdrawCollateral(market.underlying, amount, onBehalf, receiver);
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
}
