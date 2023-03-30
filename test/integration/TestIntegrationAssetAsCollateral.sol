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

        morpho.setAssetIsCollateral(dai, false);
        morpho.setAssetIsCollateralOnPool(dai, false);

        targetSender(address(this));
        targetContract(address(morpho));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.setAssetIsCollateralOnPool.selector;
        selectors[1] = this.setAssetIsCollateral.selector;

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function setAssetIsCollateralOnPool(bool isCollateral) external {
        morpho.setAssetIsCollateralOnPool(dai, isCollateral);
    }

    function setAssetIsCollateral(bool isCollateral) external {
        morpho.setAssetIsCollateral(dai, isCollateral);
    }

    function invariantAssetAsCollateral() public {
        if (morpho.market(dai).isCollateral) assertTrue(_isUsingAsCollateral(dai));
        if (!_isUsingAsCollateral(dai)) assertFalse(morpho.market(dai).isCollateral);
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

    function testSetAssetIsCollateralOnPoolShouldRevertWhenMarketIsCreatedAndIsCollateralOnMorpho() public {
        vm.prank(address(morpho));
        pool.setUserUseReserveAsCollateral(dai, true);
        morpho.setAssetIsCollateral(dai, true);

        assertEq(morpho.market(dai).isCollateral, true);
        assertEq(_isUsingAsCollateral(dai), true);

        vm.expectRevert(Errors.AssetIsCollateralOnMorpho.selector);
        morpho.setAssetIsCollateralOnPool(dai, true);

        vm.expectRevert(Errors.AssetIsCollateralOnMorpho.selector);
        morpho.setAssetIsCollateralOnPool(dai, false);
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

    function testSetAssetIsCollateralLifecycle() public {
        morpho.setAssetIsCollateralOnPool(dai, true);
        morpho.setAssetIsCollateral(dai, true);

        morpho.setAssetIsCollateral(dai, false);
        morpho.setAssetIsCollateralOnPool(dai, false);
    }

    function _isUsingAsCollateral(address underlying) internal view returns (bool) {
        return pool.getUserConfiguration(address(morpho)).isUsingAsCollateral(pool.getReserveData(underlying).id);
    }
}
