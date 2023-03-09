// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IWETHGateway} from "src/interfaces/IWETHGateway.sol";

import {WETHGateway} from "src/extensions/WETHGateway.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationEModeNative is IntegrationTest {
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    DataTypes.EModeCategory internal eModeCategory;

    function setUp() public virtual override {
        DataTypes.ReserveConfigurationMap memory stakedConfig = pool.getConfiguration(sNative);

        eModeCategoryId = uint8(stakedConfig.getEModeCategory());
        eModeCategory = pool.getEModeCategoryData(eModeCategoryId);

        super.setUp();
    }

    function testShouldLeverageStakedNative(uint256 rawCollateral, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _assumeETHReceiver(receiver);
        _prepareOnBehalf(onBehalf);

        TestMarket storage sNativeMarket = testMarkets[sNative];
        TestMarket storage wNativeMarket = testMarkets[wNative];

        rawCollateral = _boundCollateral(sNativeMarket, rawCollateral, wNativeMarket);
        uint256 quoted = wNativeMarket.quote(
            sNativeMarket, rawCollateral * (Constants.LT_LOWER_BOUND - 1) / Constants.LT_LOWER_BOUND
        );
        uint256 borrowed = quoted.percentMul(eModeCategory.ltv - 10);

        user.approve(sNative, rawCollateral);
        user.supplyCollateral(sNative, rawCollateral, onBehalf);

        user.borrow(wNative, borrowed, onBehalf, receiver);

        user.withdrawCollateral(
            sNative, quoted.percentMul(eModeCategory.liquidationThreshold - 10) - borrowed, onBehalf, receiver
        );
    }

    function testShouldNotLeverageNotStakedNative(
        uint256 rawCollateral,
        uint256 borrowed,
        address onBehalf,
        address receiver
    ) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _assumeETHReceiver(receiver);
        _prepareOnBehalf(onBehalf);

        TestMarket storage wNativeMarket = testMarkets[wNative];

        for (
            uint256 collateralMarketIndex; collateralMarketIndex < borrowableUnderlyings.length; ++collateralMarketIndex
        ) {
            _revert();

            TestMarket storage collateralMarket = testMarkets[borrowableUnderlyings[collateralMarketIndex]];

            if (collateralMarket.underlying == wNative || collateralMarket.underlying == sNative) continue;

            rawCollateral = _boundCollateral(collateralMarket, rawCollateral, wNativeMarket);
            borrowed = bound(
                borrowed,
                wNativeMarket.borrowable(collateralMarket, rawCollateral),
                wNativeMarket.quote(
                    collateralMarket, rawCollateral * (Constants.LT_LOWER_BOUND - 1) / Constants.LT_LOWER_BOUND
                ).percentMul(eModeCategory.ltv)
            );

            user.approve(collateralMarket.underlying, rawCollateral);
            user.supplyCollateral(collateralMarket.underlying, rawCollateral, onBehalf);

            vm.expectRevert(Errors.UnauthorizedBorrow.selector);
            user.borrow(wNative, borrowed, onBehalf, receiver);
        }
    }

    function testShouldNotBorrowNotNative(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            if (market.underlying == wNative || market.underlying == sNative) continue;

            amount = _boundBorrow(market, amount);

            vm.expectRevert(Errors.InconsistentEMode.selector);
            user.borrow(market.underlying, amount, onBehalf, receiver);
        }
    }
}
