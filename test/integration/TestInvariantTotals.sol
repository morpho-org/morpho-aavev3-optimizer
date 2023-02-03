// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IMorpho} from "src/interfaces/IMorpho.sol";

import {Types} from "src/libraries/Types.sol";

import "test/helpers/IntegrationTest.sol";
import "@forge-std/InvariantTest.sol";

contract MorphoWrapper {
    uint256 internal constant MAX_ITERATIONS = 10;
    IMorpho internal immutable MORPHO;
    address internal immutable UNDERLYING;

    constructor(address _morpho, address underlying) {
        MORPHO = IMorpho(_morpho);
        UNDERLYING = underlying;
    }

    function supply(uint256 amount, address onBehalf) external {
        console2.log("0");
        MORPHO.supply(UNDERLYING, amount, onBehalf, MAX_ITERATIONS);
    }

    function supplyCollateral(uint256 amount, address onBehalf) external {
        MORPHO.supplyCollateral(UNDERLYING, amount, onBehalf);
    }

    function borrow(uint256 amount, address onBehalf, address receiver) external {
        MORPHO.borrow(UNDERLYING, amount, onBehalf, receiver, MAX_ITERATIONS);
    }

    function repay(uint256 amount, address onBehalf) external {
        MORPHO.repay(UNDERLYING, amount, onBehalf);
    }

    function withdraw(uint256 amount, address onBehalf, address receiver) external {
        MORPHO.withdraw(UNDERLYING, amount, onBehalf, receiver);
    }

    function withdrawCollateral(uint256 amount, address onBehalf, address receiver) external {
        MORPHO.withdrawCollateral(UNDERLYING, amount, onBehalf, receiver);
    }

    function liquidate(address user, uint256 amount) external {
        MORPHO.liquidate(UNDERLYING, UNDERLYING, user, amount);
    }

    function market() external view returns (Types.Market memory) {
        return MORPHO.market(UNDERLYING);
    }

    function updatedIndexes() external view returns (Types.Indexes256 memory) {
        return MORPHO.updatedIndexes(UNDERLYING);
    }
}

contract TestInvariantTotals is IntegrationTest, InvariantTest {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    uint256 constant SUPPLY_CAP = 1;
    uint256 constant BORROW_CAP = 1e8;

    MorphoWrapper internal morphoWrapper;

    function setUp() public override {
        super.setUp();

        console.log("setup");

        morphoWrapper = new MorphoWrapper(address(morpho), dai);

        // targetContract(address(morphoWrapper));
        // targetSelector(getSelectors());
    }

    function getSelectors() public view returns (InvariantTest.FuzzSelector memory targets) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = MorphoWrapper.supply.selector;
        selectors[1] = MorphoWrapper.supplyCollateral.selector;
        selectors[2] = MorphoWrapper.borrow.selector;
        selectors[3] = MorphoWrapper.repay.selector;
        selectors[4] = MorphoWrapper.withdraw.selector;
        selectors[5] = MorphoWrapper.withdrawCollateral.selector;
        selectors[6] = MorphoWrapper.liquidate.selector;
        targets = InvariantTest.FuzzSelector(address(morphoWrapper), selectors);
    }

    function invariantTotals() public {
        targetContract(address(morphoWrapper));
        targetSelector(getSelectors());

        Types.Market memory market = morphoWrapper.market();
        Types.Deltas memory deltas = market.deltas;
        Types.Indexes256 memory indexes = morphoWrapper.updatedIndexes();

        // Check that test is healthy.

        assertEq(market.underlying, dai);
        assertGt(indexes.supply.p2pIndex, 0);

        // Set supply and borrow caps.

        DataTypes.ReserveConfigurationMap memory reserveConfig = pool.getConfiguration(dai);
        reserveConfig.setSupplyCap(SUPPLY_CAP);
        reserveConfig.setBorrowCap(BORROW_CAP);
        assertEq(reserveConfig.getSupplyCap(), SUPPLY_CAP);
        assertEq(reserveConfig.getBorrowCap(), BORROW_CAP);

        vm.prank(address(poolConfigurator));
        pool.setConfiguration(dai, reserveConfig);

        reserveConfig = pool.getConfiguration(dai);

        // Should obviously not always be equal to 0.
        assertEq(deltas.supply.scaledTotalP2P, 0);
        assertEq(
            deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex)
                - deltas.supply.scaledDeltaPool.rayMul(indexes.supply.poolIndex),
            0
        );
    }
}
