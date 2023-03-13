// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./IntegrationTest.sol";

contract InvariantHandler is IntegrationTest {
    using SafeTransferLib for ERC20;

    function supply(uint256 seed, uint256 amount, address onBehalf, uint256 maxIterations) external {
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        amount = _boundSupply(market, amount);
        onBehalf = _boundAddressNotZero(onBehalf);

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
}
