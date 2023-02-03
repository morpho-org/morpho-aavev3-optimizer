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

    function supply(uint256 amount) external {
        MORPHO.supply(UNDERLYING, amount, address(0xdead), MAX_ITERATIONS);
    }

    function supplyCollateral(uint256 amount) external {
        MORPHO.supplyCollateral(UNDERLYING, amount, address(0xdead));
    }

    function borrow(uint256 amount, address receiver) external {
        MORPHO.borrow(UNDERLYING, amount, address(0xdead), receiver, MAX_ITERATIONS);
    }

    function repay(uint256 amount) external {
        MORPHO.repay(UNDERLYING, amount, address(0xdead));
    }

    function withdraw(uint256 amount, address receiver) external {
        MORPHO.withdraw(UNDERLYING, amount, address(0xdead), receiver);
    }

    function withdrawCollateral(uint256 amount, address receiver) external {
        MORPHO.withdrawCollateral(UNDERLYING, amount, address(0xdead), receiver);
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
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    uint256 constant SUPPLY_CAP = 1;
    uint256 constant BORROW_CAP = 1e8;

    address aDai = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address vDai = 0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC;

    MorphoWrapper internal morphoWrapper;

    function setUp() public override {
        super.setUp();

        console.log("setup");

        morphoWrapper = new MorphoWrapper(address(morpho), dai);

        deal(dai, address(morphoWrapper), type(uint256).max);

        vm.prank(address(morphoWrapper));
        ERC20(dai).safeApprove(address(morpho), type(uint256).max);

        targetContract(address(morphoWrapper));
        targetSender(address(0xdead));
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
        assertEq(IVariableDebtToken(vDai).scaledBalanceOf(address(morphoWrapper)), 0);
        assertEq(IAToken(aDai).balanceOf(address(morphoWrapper)), 0);
        assertEq(deltas.supply.scaledTotalP2P, 0);
        assertEq(
            deltas.supply.scaledTotalP2P.rayMul(indexes.supply.p2pIndex)
                - deltas.supply.scaledDeltaPool.rayMul(indexes.supply.poolIndex),
            0
        );
    }
}
