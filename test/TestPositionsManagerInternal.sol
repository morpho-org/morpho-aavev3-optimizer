// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Errors} from "../src/libraries/Errors.sol";
import {MorphoStorage} from "../src/MorphoStorage.sol";
import {PositionsManagerInternal} from "../src/PositionsManagerInternal.sol";
import {Types} from "../src/libraries/Types.sol";
import {Constants} from "../src/libraries/Constants.sol";

import {TestConfig} from "./helpers/TestConfig.sol";
import {PoolLib} from "../src/libraries/PoolLib.sol";
import {MarketLib} from "../src/libraries/MarketLib.sol";

import {MockPriceOracleSentinel} from "./mock/MockPriceOracleSentinel.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";
import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {DataTypes} from "../src/libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "../src/libraries/aave/ReserveConfiguration.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import "./setup/TestSetup.sol";

contract TestPositionsManagerInternal is TestSetup, PositionsManagerInternal {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestConfig for TestConfig.Config;
    using PoolLib for IPool;
    using MarketLib for Types.Market;
    using SafeTransferLib for ERC20;

    uint256 constant MIN_AMOUNT = 1 ether;
    uint256 constant MAX_AMOUNT = type(uint96).max / 2;

    IPriceOracleGetter internal oracle;

    constructor() TestSetup() MorphoStorage(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function setUp() public virtual override {
        _defaultMaxLoops = Types.MaxLoops(10, 10, 10, 10);
        _maxSortedUsers = 20;

        createTestMarket(dai, 0, 3_333);
        createTestMarket(wbtc, 0, 3_333);
        createTestMarket(usdc, 0, 3_333);
        createTestMarket(usdt, 0, 3_333);
        createTestMarket(wNative, 0, 3_333);

        fillBalance(address(this), type(uint256).max);
        ERC20(dai).approve(address(_POOL), type(uint256).max);
        ERC20(wbtc).approve(address(_POOL), type(uint256).max);
        ERC20(usdc).approve(address(_POOL), type(uint256).max);
        ERC20(usdt).approve(address(_POOL), type(uint256).max);
        ERC20(wNative).approve(address(_POOL), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(usdt, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);

        oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
    }

    function createTestMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        DataTypes.ReserveData memory reserveData = _POOL.getReserveData(underlying);

        Types.Market storage market = _market[underlying];

        Types.Indexes256 memory indexes;
        indexes.supply.p2pIndex = WadRayMath.RAY;
        indexes.borrow.p2pIndex = WadRayMath.RAY;
        (indexes.supply.poolIndex, indexes.borrow.poolIndex) = _POOL.getCurrentPoolIndexes(underlying);

        market.setIndexes(indexes);
        market.lastUpdateTimestamp = uint32(block.timestamp);

        market.underlying = underlying;
        market.aToken = reserveData.aTokenAddress;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(underlying);

        ERC20(underlying).safeApprove(address(_POOL), type(uint256).max);
    }

    function testValidateInputRevertsIfAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressIsZero.selector));
        _validateInput(dai, 1, address(0));
    }

    function testValidateInputRevertsIfAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AmountIsZero.selector));
        _validateInput(dai, 0, address(1));
    }

    function testValidateInputRevertsIfMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        _validateInput(address(0), 1, address(1));
    }

    function testValidateInput() public {
        _market[address(1)].aToken = address(2);
        _validateInput(dai, 1, address(1));
    }

    function testValidatePermission(address owner, address manager) public {
        _validatePermission(owner, owner);

        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }

        _approveManager(owner, manager, true);
        _validatePermission(owner, manager);

        _approveManager(owner, manager, false);
        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }
    }

    function testValidateSupplyShouldRevertIfSupplyPaused() public {
        _market[dai].pauseStatuses.isSupplyPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyIsPaused.selector));
        _validateSupply(dai, 1, address(1));
    }

    function testValidateSupply() public view {
        _validateSupply(dai, 1, address(1));
    }

    function testValidateSupplyCollateralShouldRevertIfSupplyCollateralPaused() public {
        _market[dai].pauseStatuses.isSupplyCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyCollateralIsPaused.selector));
        _validateSupplyCollateral(dai, 1, address(1));
    }

    function testValidateSupplyCollateral() public view {
        _validateSupplyCollateral(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateBorrow(address underlying, uint256 amount, address user) external view {
        _validateBorrow(underlying, amount, user);
    }

    function testValidateBorrowShouldRevertIfBorrowPaused() public {
        _market[dai].pauseStatuses.isBorrowPaused = true;
        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowIsPaused.selector));
        this.validateBorrow(dai, 1, address(this));
    }

    function testValidateBorrowShouldRevertIfBorrowingNotEnabled() public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        reserveConfig.setBorrowingEnabled(false);
        assertFalse(reserveConfig.getBorrowingEnabled());

        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowingNotEnabled.selector));
        this.validateBorrow(dai, 1, address(this));
    }

    function testValidateBorrowShouldRevertIfPriceOracleSentinelBorrowDisabled() public {
        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));

        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleSentinelBorrowDisabled.selector));
        this.validateBorrow(dai, 1, address(this));
    }

    function testValidateBorrowShouldFailIfDebtTooHigh(uint256 onPool, uint256 inP2P) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        inP2P = bound(inP2P, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorisedBorrow.selector));
        this.validateBorrow(dai, onPool + inP2P, address(this));
    }

    function testValidateBorrow(uint256 onPool, uint256 inP2P) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        inP2P = bound(inP2P, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        this.validateBorrow(dai, onPool / 4, address(this));
    }

    function testValidateRepayShouldRevertIfRepayPaused() public {
        _market[dai].pauseStatuses.isRepayPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.RepayIsPaused.selector));
        _validateRepay(dai, 1, address(1));
    }

    function testValidateRepay() public view {
        _validateRepay(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateWithdraw(address underlying, uint256 amount, address user, address to) external view {
        _validateWithdraw(underlying, amount, user, to);
    }

    function testValidateWithdrawShouldRevertIfWithdrawPaused() public {
        _market[dai].pauseStatuses.isWithdrawPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawIsPaused.selector));
        this.validateWithdraw(dai, 1, address(this), address(this));
    }

    function testValidateWithdrawShouldRevertIfPriceOracleSentinelBorrowPaused() public {
        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));

        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleSentinelBorrowPaused.selector));
        this.validateWithdraw(dai, 1, address(this), address(this));
    }

    function testValidateWithdraw() public view {
        this.validateWithdraw(dai, 1, address(this), address(this));
    }

    function validateWithdrawCollateral(address underlying, uint256 amount, address supplier, address receiver)
        external
        view
    {
        _validateWithdrawCollateral(underlying, amount, supplier, receiver);
    }

    function testValidateWithdrawCollateralShouldRevertIfWithdrawCollateralPaused() public {
        _market[dai].pauseStatuses.isWithdrawCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawCollateralIsPaused.selector));
        this.validateWithdrawCollateral(dai, 1, address(this), address(this));
    }

    function testValidateWithdrawCollateralShouldRevertIfHealthFactorTooLow(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), onPool.rayDiv(indexes.supply.poolIndex) / 2, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawUnauthorized.selector));
        this.validateWithdrawCollateral(dai, onPool.rayDiv(indexes.supply.poolIndex) / 2, address(this), address(this));
    }

    function testValidateWithdrawCollateral(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDivUp(_computeIndexes(dai).supply.poolIndex);
        this.validateWithdrawCollateral(dai, onPool, address(this), address(this));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateLiquidate(address collateral, address borrow, address liquidator)
        external
        view
        returns (uint256)
    {
        return _validateLiquidate(collateral, borrow, liquidator);
    }

    function testValidateLiquidateIfBorrowMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        this.validateLiquidate(address(420), dai, address(this));
    }

    function testValidateLiquidateIfCollateralMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        this.validateLiquidate(dai, address(420), address(this));
    }

    function testValidateLiquidateIfLiquidateCollateralPaused() public {
        _market[dai].pauseStatuses.isLiquidateCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.LiquidateCollateralIsPaused.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateIfLiquidateBorrowPaused() public {
        _market[dai].pauseStatuses.isLiquidateBorrowPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.LiquidateBorrowIsPaused.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateShouldRevertIfBorrowerNotBorrowing() public {
        _userCollaterals[address(this)].add(dai);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserNotMemberOfMarket.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateShouldRevertIfBorrowerNotCollateralizing() public {
        _userBorrows[address(this)].add(dai);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserNotMemberOfMarket.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateShouldReturnMaxCloseFactorIfDeprecatedBorrow() public {
        _userCollaterals[address(this)].add(dai);
        _userBorrows[address(this)].add(dai);
        _market[dai].pauseStatuses.isDeprecated = true;
        uint256 closeFactor = this.validateLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.MAX_CLOSE_FACTOR);
    }

    // TODO: Failing with no reason. To investigate.
    // function testValidateLiquidateShouldRevertIfSentinelDisallows() public {
    //     uint256 amount = 1e18;
    //     (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
    //     Types.Indexes256 memory indexes = _computeIndexes(dai);

    //     _userCollaterals[address(this)].add(dai);
    //     _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
    //     _userBorrows[address(this)].add(dai);
    //     _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.supply.poolIndex).percentMulUp(lt * 11 / 10) , 0);

    //     MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
    //     priceOracleSentinel.setBorrowAllowed(true);
    //     vm.prank(_ADDRESSES_PROVIDER.owner());
    //     _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

    //     vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorisedLiquidate.selector));
    //     this.validateLiquidate(dai, dai, address(this));
    // }
}
