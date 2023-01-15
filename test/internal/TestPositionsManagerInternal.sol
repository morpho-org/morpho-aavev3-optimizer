// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Errors} from "src/libraries/Errors.sol";
import {MorphoStorage} from "src/MorphoStorage.sol";
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";

import {Types} from "src/libraries/Types.sol";
import {Constants} from "src/libraries/Constants.sol";

import {TestConfigLib, TestConfig} from "../helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";

import {MockPriceOracleSentinel} from "../mock/MockPriceOracleSentinel.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";
import {IPool, IPoolAddressesProvider} from "src/interfaces/aave/IPool.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {DataTypes} from "src/libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "src/libraries/aave/ReserveConfiguration.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import "test/helpers/InternalTest.sol";

contract TestPositionsManager is InternalTest, PositionsManagerInternal {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using MarketLib for Types.Market;
    using SafeTransferLib for ERC20;

    uint256 constant MIN_AMOUNT = 1 ether;
    uint256 constant MAX_AMOUNT = type(uint96).max / 2;

    IPriceOracleGetter internal oracle;
    address internal poolConfigurator;

    function setUp() public virtual override {
        poolConfigurator = addressesProvider.getPoolConfigurator();

        _defaultMaxLoops = Types.MaxLoops(10, 10, 10, 10);
        _maxSortedUsers = 20;

        _createMarket(dai, 0, 3_333);
        _createMarket(wbtc, 0, 3_333);
        _createMarket(usdc, 0, 3_333);
        _createMarket(usdt, 0, 3_333);
        _createMarket(wNative, 0, 3_333);

        _setBalances(address(this), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(usdt, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);

        oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
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

    function testValidateSupplyInputShouldRevertIfSupplyPaused() public {
        _market[dai].pauseStatuses.isSupplyPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyIsPaused.selector));
        _validateSupplyInput(dai, 1, address(1));
    }

    function testValidateSupplyInput() public view {
        _validateSupplyInput(dai, 1, address(1));
    }

    function testValidateSupplyCollateralShouldRevertIfSupplyCollateralPaused() public {
        _market[dai].pauseStatuses.isSupplyCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyCollateralIsPaused.selector));
        _validateSupplyCollateralInput(dai, 1, address(1));
    }

    function testValidateSupplyCollateralInput() public view {
        _validateSupplyCollateralInput(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateBorrowInput(address underlying, uint256 amount, address user) external view {
        _validateBorrowInput(underlying, amount, user);
    }

    function validateBorrow(address underlying, uint256 amount, address user) external view {
        _validateBorrow(underlying, amount, user);
    }

    function testValidateBorrowInputShouldRevertIfBorrowPaused() public {
        _market[dai].pauseStatuses.isBorrowPaused = true;
        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowIsPaused.selector));
        this.validateBorrowInput(dai, 1, address(this));
    }

    function testValidateBorrowInputShouldRevertIfBorrowingNotEnabled() public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        reserveConfig.setBorrowingEnabled(false);
        assertFalse(reserveConfig.getBorrowingEnabled());

        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowingNotEnabled.selector));
        this.validateBorrowInput(dai, 1, address(this));
    }

    function testValidateBorrowInputShouldRevertIfPriceOracleSentinelBorrowDisabled() public {
        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
        priceOracleSentinel.setBorrowAllowed(false);

        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleSentinelBorrowDisabled.selector));
        this.validateBorrowInput(dai, 1, address(this));
    }

    function testValidateBorrowShouldFailIfDebtTooHigh(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedBorrow.selector));
        this.validateBorrow(dai, onPool, address(this));
    }

    function testValidateBorrowInput(uint256 onPool, uint256 inP2P) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        inP2P = bound(inP2P, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        this.validateBorrowInput(dai, onPool / 4, address(this));
    }

    function testValidateRepayInputShouldRevertIfRepayPaused() public {
        _market[dai].pauseStatuses.isRepayPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.RepayIsPaused.selector));
        _validateRepayInput(dai, 1, address(1));
    }

    function testValidateRepayInput() public view {
        _validateRepayInput(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateWithdrawInput(address underlying, uint256 amount, address user, address to) external view {
        _validateWithdrawInput(underlying, amount, user, to);
    }

    function testValidateWithdrawInputShouldRevertIfWithdrawPaused() public {
        _market[dai].pauseStatuses.isWithdrawPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawIsPaused.selector));
        this.validateWithdrawInput(dai, 1, address(this), address(this));
    }

    function testValidateWithdrawInputShouldRevertIfPriceOracleSentinelBorrowPaused() public {
        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
        priceOracleSentinel.setBorrowAllowed(false);

        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleSentinelBorrowPaused.selector));
        this.validateWithdrawInput(dai, 1, address(this), address(this));
    }

    function testValidateWithdraw() public view {
        this.validateWithdrawInput(dai, 1, address(this), address(this));
    }

    function validateWithdrawCollateralInput(address underlying, uint256 amount, address supplier, address receiver)
        external
        view
    {
        _validateWithdrawCollateralInput(underlying, amount, supplier, receiver);
    }

    function testValidateWithdrawCollateralShouldRevertIfWithdrawCollateralPaused() public {
        _market[dai].pauseStatuses.isWithdrawCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawCollateralIsPaused.selector));
        this.validateWithdrawCollateralInput(dai, 1, address(this), address(this));
    }

    function testValidateWithdrawCollateralInputShouldRevertIfHealthFactorTooLow(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), onPool.rayDiv(indexes.borrow.poolIndex) / 2, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedWithdraw.selector));
        _validateWithdrawCollateral(dai, onPool.rayDiv(indexes.supply.poolIndex) / 2, address(this));
    }

    function testValidateWithdrawCollateralInput(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDivUp(_computeIndexes(dai).supply.poolIndex);
        this.validateWithdrawCollateralInput(dai, onPool, address(this), address(this));
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

    function testValidateLiquidateShouldRevertIfSentinelDisallows() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 101 / 100), 0);

        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
        priceOracleSentinel.setLiquidationAllowed(false);
        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedLiquidate.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateShouldRevertIfBorrowerHealthy() public {
        uint256 amount = 1e18;
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulDown(50_00), 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedLiquidate.selector));
        this.validateLiquidate(dai, dai, address(this));
    }

    function testValidateLiquidateShouldReturnMaxCloseFactorIfBelowMinThreshold() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 11 / 10), 0);

        uint256 closeFactor = this.validateLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.MAX_CLOSE_FACTOR);
    }

    function testValidateLiquidateShouldReturnDefaultCloseFactorIfAboveMinThreshold() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 101 / 100), 0);

        uint256 closeFactor = this.validateLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.DEFAULT_CLOSE_FACTOR);
    }
}
