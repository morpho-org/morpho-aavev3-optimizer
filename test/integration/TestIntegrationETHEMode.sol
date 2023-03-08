// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IWETHGateway} from "src/interfaces/IWETHGateway.sol";

import {WETHGateway} from "src/extensions/WETHGateway.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationETHEMode is IntegrationTest {
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IWETHGateway internal wethGateway;
    DataTypes.EModeCategory internal eModeCategory;

    function setUp() public virtual override {
        DataTypes.ReserveConfigurationMap memory stakedConfig = pool.getConfiguration(sNative);

        eModeCategoryId = uint8(stakedConfig.getEModeCategory());
        eModeCategory = pool.getEModeCategoryData(eModeCategoryId);

        super.setUp();

        wethGateway = new WETHGateway(address(morpho));
    }

    function testLeverageStakedNative(uint256 collateral, address onBehalf, address receiver) public {
        receiver = _boundReceiver(receiver);
        onBehalf = _boundOnBehalf(onBehalf);

        _assumeETHReceiver(receiver);
        _prepareOnBehalf(onBehalf);

        TestMarket storage sNativeMarket = testMarkets[sNative];
        TestMarket storage wNativeMarket = testMarkets[wNative];

        collateral = _boundCollateral(sNativeMarket, collateral, wNativeMarket);
        uint256 collateralized =
            (collateralValue(collateral) * sNativeMarket.price * 1 ether) / (wNativeMarket.price * 1 ether);

        uint256 borrowed = collateralized.percentMul(eModeCategory.ltv - 10);

        user.approve(sNative, collateral);
        user.supplyCollateral(sNative, collateral, onBehalf);

        vm.startPrank(onBehalf);
        morpho.approveManager(address(wethGateway), true);
        wethGateway.borrowETH(borrowed, receiver, DEFAULT_MAX_ITERATIONS);
        vm.stopPrank();

        user.withdrawCollateral(
            sNative, collateralized.percentMul(eModeCategory.liquidationThreshold - 10) - borrowed, onBehalf, receiver
        );
    }
}
