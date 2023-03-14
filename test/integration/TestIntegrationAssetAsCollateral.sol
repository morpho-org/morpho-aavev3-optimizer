// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";

import {Errors} from "src/libraries/Errors.sol";
import {UserConfiguration} from "@aave-v3-core/protocol/libraries/configuration/UserConfiguration.sol";

import {Morpho} from "src/Morpho.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationAssetAsCollateral is IntegrationTest {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    function setUp() public override {
        super.setUp();

        // Deposit LINK dust so that setting LINK as collateral does not revert on the pool.
        _depositSimple(link, 1e12, address(morpho));

        morpho.setAssetIsCollateral(dai, false);
        morpho.setAssetIsCollateral(usdc, false);
        morpho.setAssetIsCollateral(aave, false);
        morpho.setAssetIsCollateral(wbtc, false);
        morpho.setAssetIsCollateral(weth, false);

        vm.startPrank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, false);
        pool.setUserUseReserveAsCollateral(usdc, false);
        pool.setUserUseReserveAsCollateral(aave, false);
        pool.setUserUseReserveAsCollateral(wbtc, false);
        pool.setUserUseReserveAsCollateral(weth, false);
        pool.setUserUseReserveAsCollateral(link, false);
        vm.stopPrank();
    }

    function testSetAssetIsCollateralShouldRevertWhenMarketNotCreated(address underlying) public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setAssetIsCollateral(underlying, true);
    }

    function testSetAssetIsCollateralShouldRevertWhenMarketNotCollateralOnPool() public {
        assertEq(_isUsingAsCollateral(dai), false);

        vm.expectRevert(Errors.AssetNotCollateralOnPool.selector);
        morpho.setAssetIsCollateral(dai, true);

        vm.expectRevert(Errors.AssetNotCollateralOnPool.selector);
        morpho.setAssetIsCollateral(dai, false);
    }

    function testSetAssetIsCollateral() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);

        morpho.setAssetIsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, true);
        assertEq(_isUsingAsCollateral(dai), true);
    }

    function testSetAssetIsNotCollateral() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);

        morpho.setAssetIsCollateral(dai, false);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);
    }

    function testSetAssetIsCollateralOnPoolShouldRevertWhenMarketIsNotCreated() public {
        assertEq(morpho.market(link).isCollateral, false);
        assertEq(pool.getUserConfiguration(address(morpho)).isUsingAsCollateral(pool.getReserveData(link).id), false);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setAssetIsCollateralOnPool(link, true);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        morpho.setAssetIsCollateralOnPool(link, false);
    }

    function testSetAssetIsCollateralOnPoolShouldRevertWhenMarketIsCollateralOnMorpho() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);
        morpho.setAssetIsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, true);
        assertEq(_isUsingAsCollateral(dai), true);

        vm.expectRevert(Errors.AssetIsCollateralOnMorpho.selector);
        morpho.setAssetIsCollateralOnPool(dai, false);
    }

    function testSetAssetIsCollateralOnPoolWhenMarketIsCreatedAndIsCollateralOnMorphoAndOnPool() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);
        morpho.setAssetIsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, true);
        assertEq(_isUsingAsCollateral(dai), true);

        morpho.setAssetIsCollateralOnPool(dai, true);

        assertEq(morpho.market(dai).isCollateral, true);
        assertEq(_isUsingAsCollateral(dai), true);
    }

    function testSetAssetIsCollateralOnPoolWhenMarketIsCreatedAndIsNotCollateralOnMorphoOnly() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);

        morpho.setAssetIsCollateralOnPool(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);
    }

    function testSetAssetIsCollateralOnPoolWhenMarketIsCreatedAndIsNotCollateral() public {
        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), false);

        morpho.setAssetIsCollateralOnPool(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);
    }

    function testSetAssetIsNotCollateralOnPoolWhenMarketIsCreatedAndIsNotCollateralOnMorphoOnly() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), true);

        morpho.setAssetIsCollateralOnPool(dai, false);

        assertEq(morpho.market(dai).isCollateral, false);
        assertEq(_isUsingAsCollateral(dai), false);
    }

    function _isUsingAsCollateral(address underlying) internal view returns (bool) {
        return pool.getUserConfiguration(address(morpho)).isUsingAsCollateral(pool.getReserveData(underlying).id);
    }

    function testSetAssetIsCollateralLifecycle() public {
        morpho.setAssetIsCollateralOnPool(dai, true);
        morpho.setAssetIsCollateral(dai, true);

        morpho.setAssetIsCollateral(dai, false);
        morpho.setAssetIsCollateralOnPool(dai, false);
    }
}
