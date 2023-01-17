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
    using Math for uint256;

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
    function validateBorrowInput(address underlying, uint256 amount, address borrower, address receiver)
        external
        view
    {
        _validateBorrowInput(underlying, amount, borrower, receiver);
    }

    function validateBorrow(address underlying, uint256 amount, address user) external view {
        _validateBorrow(underlying, amount, user);
    }

    function testValidateBorrowInputShouldRevertIfBorrowPaused() public {
        _market[dai].pauseStatuses.isBorrowPaused = true;
        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowIsPaused.selector));
        this.validateBorrowInput(dai, 1, address(this), address(this));
    }

    function testValidateBorrowInputShouldRevertIfBorrowingNotEnabled() public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        reserveConfig.setBorrowingEnabled(false);
        assertFalse(reserveConfig.getBorrowingEnabled());

        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowingNotEnabled.selector));
        this.validateBorrowInput(dai, 1, address(this), address(this));
    }

    function testValidateBorrowInputShouldRevertIfPriceOracleSentinelBorrowDisabled() public {
        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
        priceOracleSentinel.setBorrowAllowed(false);

        vm.prank(_ADDRESSES_PROVIDER.owner());
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleSentinelBorrowDisabled.selector));
        this.validateBorrowInput(dai, 1, address(this), address(this));
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

        this.validateBorrowInput(dai, onPool / 4, address(this), address(this));
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

    function validateWithdrawCollateral(address underlying, uint256 amount, address supplier) external view {
        _validateWithdrawCollateral(underlying, amount, supplier);
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
        this.validateWithdrawCollateral(dai, onPool.rayDiv(indexes.supply.poolIndex) / 2, address(this));
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

    function testAddToPool(uint256 amount, uint256 onPool, uint256 poolIndex) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        onPool = bound(onPool, 0, MAX_AMOUNT);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 10);

        (uint256 newAmount, uint256 newOnPool) = _addToPool(amount, onPool, poolIndex);
        assertEq(newAmount, amount);
        assertEq(newOnPool, onPool + amount.rayDiv(poolIndex));
    }

    function testSubFromPool(uint256 amount, uint256 onPool, uint256 poolIndex) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        onPool = bound(onPool, 0, MAX_AMOUNT);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 10);

        (uint256 newAmount, uint256 newAmountLeft, uint256 newOnPool) = _subFromPool(amount, onPool, poolIndex);
        assertEq(newAmount, Math.min(onPool.rayMul(poolIndex), amount));
        assertEq(newAmountLeft, amount - newAmount);
        assertEq(newOnPool, onPool - Math.min(onPool, newAmount.rayDiv(poolIndex)));
    }

    function testPromoteSuppliersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            _updateSupplierInDS(dai, vm.addr(i + 1), uint256(1 ether).rayDiv(indexes.supply.poolIndex), 0);
        }

        Types.PromoteVars memory vars = Types.PromoteVars({
            underlying: dai,
            amount: amount,
            poolIndex: indexes.supply.poolIndex,
            maxLoops: maxLoops,
            promote: _promoteSuppliers
        });

        (uint256 toProcess, uint256 amountLeft, uint256 maxLoopsLeft) =
            _promoteRoutine(vars, _marketBalances[dai].poolSuppliers, _market[dai].deltas.supply);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);
        uint256 expectedLoops = amount > 1 ether * maxExpectedLoops ? maxExpectedLoops : amount.divUp(1 ether);

        uint256 expectedToProcess = Math.min(amount, expectedLoops * 1 ether);
        uint256 expectedAmountLeft = amount - expectedToProcess;
        uint256 expectedMaxLoopsLeft = maxLoops - expectedLoops;
        assertEq(toProcess, expectedToProcess, "toProcess");
        assertEq(amountLeft, expectedAmountLeft, "amountLeft");
        assertEq(maxLoopsLeft, expectedMaxLoopsLeft, "maxLoopsLeft");
        assertEq(_market[dai].deltas.supply.scaledTotalP2P, expectedToProcess.rayDiv(indexes.supply.poolIndex), "delta");
    }

    function testPromoteBorrowersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            _updateBorrowerInDS(dai, vm.addr(i + 1), uint256(1 ether).rayDiv(indexes.borrow.poolIndex), 0);
        }

        Types.PromoteVars memory vars = Types.PromoteVars({
            underlying: dai,
            amount: amount,
            poolIndex: indexes.borrow.poolIndex,
            maxLoops: maxLoops,
            promote: _promoteBorrowers
        });

        (uint256 toProcess, uint256 amountLeft, uint256 maxLoopsLeft) =
            _promoteRoutine(vars, _marketBalances[dai].poolBorrowers, _market[dai].deltas.borrow);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);
        uint256 expectedLoops = amount > 1 ether * maxExpectedLoops ? maxExpectedLoops : amount.divUp(1 ether);

        uint256 expectedToProcess = Math.min(amount, maxExpectedLoops * 1 ether);
        uint256 expectedAmountLeft = amount - expectedToProcess;
        uint256 expectedMaxLoopsLeft = maxLoops - expectedLoops;
        assertEq(toProcess, expectedToProcess, "toProcess");
        assertEq(amountLeft, expectedAmountLeft, "amountLeft");
        assertEq(maxLoopsLeft, expectedMaxLoopsLeft, "maxLoopsLeft");
        assertEq(_market[dai].deltas.borrow.scaledTotalP2P, expectedToProcess.rayDiv(indexes.borrow.poolIndex), "delta");
    }

    function testDemoteSuppliersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            uint256 amountPerSupplier = uint256(1 ether).rayDiv(indexes.supply.p2pIndex);
            _updateSupplierInDS(dai, vm.addr(i + 1), 0, amountPerSupplier);
            _market[dai].deltas.supply.scaledTotalP2P += amountPerSupplier;
        }

        uint256 totalScaledP2PBefore = _market[dai].deltas.supply.scaledTotalP2P;

        uint256 toProcess = _demoteRoutine(dai, amount, maxLoops, indexes, _demoteSuppliers, _market[dai].deltas, false);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);

        uint256 expectedToProcess = Math.min(amount, maxExpectedLoops * 1 ether);
        uint256 expectedTotalScaledP2P = totalScaledP2PBefore - expectedToProcess.rayDiv(indexes.supply.p2pIndex);

        assertEq(toProcess, amount, "toProcess");

        assertEq(
            _market[dai].deltas.supply.scaledDeltaPool,
            amount > expectedToProcess ? (amount - expectedToProcess).rayDiv(indexes.supply.poolIndex) : 0,
            "delta"
        );
        assertEq(_market[dai].deltas.supply.scaledTotalP2P, expectedTotalScaledP2P, "scaled p2p supply");
    }

    function testDemoteBorrowersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            uint256 amountPerBorrower = uint256(1 ether).rayDiv(indexes.borrow.p2pIndex);
            _updateBorrowerInDS(dai, vm.addr(i + 1), 0, amountPerBorrower);
            _market[dai].deltas.borrow.scaledTotalP2P += amountPerBorrower;
        }

        uint256 totalScaledP2PBefore = _market[dai].deltas.borrow.scaledTotalP2P;

        uint256 toProcess = _demoteRoutine(dai, amount, maxLoops, indexes, _demoteBorrowers, _market[dai].deltas, true);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);

        uint256 expectedToProcess = Math.min(amount, maxExpectedLoops * 1 ether);
        uint256 expectedTotalScaledP2P = totalScaledP2PBefore - expectedToProcess.rayDiv(indexes.borrow.p2pIndex);

        assertEq(toProcess, amount, "toProcess");

        assertEq(
            _market[dai].deltas.borrow.scaledDeltaPool,
            amount > expectedToProcess ? (amount - expectedToProcess).rayDiv(indexes.borrow.poolIndex) : 0,
            "delta"
        );
        assertEq(_market[dai].deltas.borrow.scaledTotalP2P, expectedTotalScaledP2P, "scaled p2p borrow");
    }

    function testMatchDeltaSupply(uint256 amount, uint256 delta) public {
        amount = bound(amount, 0, 20 ether);
        delta = bound(delta, 0, 20 ether);

        Types.MarketSideDelta storage supplyDelta = _market[dai].deltas.supply;
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        supplyDelta.scaledDeltaPool = delta;
        (uint256 toProcess, uint256 amountLeft) = _matchDelta(dai, amount, indexes.supply.poolIndex, false);

        uint256 expectedMatched = Math.min(delta.rayMul(indexes.supply.poolIndex), amount);

        assertEq(toProcess, expectedMatched, "toProcess");
        assertEq(amountLeft, amount - expectedMatched, "amountLeft");
        assertEq(supplyDelta.scaledDeltaPool, delta - expectedMatched.rayDiv(indexes.supply.poolIndex), "delta");
    }

    function testMatchDeltaBorrow(uint256 amount, uint256 delta) public {
        amount = bound(amount, 0, 20 ether);
        delta = bound(delta, 0, 20 ether);

        Types.MarketSideDelta storage borrowDelta = _market[dai].deltas.borrow;
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        borrowDelta.scaledDeltaPool = delta;
        (uint256 toProcess, uint256 amountLeft) = _matchDelta(dai, amount, indexes.borrow.poolIndex, true);

        uint256 expectedMatched = Math.min(delta.rayMul(indexes.borrow.poolIndex), amount);

        assertEq(toProcess, expectedMatched, "toProcess");
        assertEq(amountLeft, amount - expectedMatched, "amountLeft");
        assertEq(borrowDelta.scaledDeltaPool, delta - expectedMatched.rayDiv(indexes.borrow.poolIndex), "delta");
    }

    function testUpdateDeltaP2PSupplyAmount(uint256 amount, uint256 totalP2P) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        totalP2P = bound(totalP2P, 0, MAX_AMOUNT);
        Types.Deltas storage deltas = _market[dai].deltas;
        deltas.supply.scaledTotalP2P = totalP2P;

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        uint256 inP2P = _updateP2PDelta(dai, amount, indexes.supply.p2pIndex, 0, deltas.supply);

        uint256 expectedInP2P = amount.rayDiv(indexes.supply.p2pIndex);
        uint256 expectedInTotalScaledP2P = totalP2P + expectedInP2P;

        assertEq(inP2P, expectedInP2P, "inP2P");
        assertEq(deltas.supply.scaledTotalP2P, expectedInTotalScaledP2P, "totalScaledP2P");
    }

    function testUpdateDeltaP2PBorrowAmount(uint256 amount, uint256 totalP2P) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        totalP2P = bound(totalP2P, 0, MAX_AMOUNT);
        Types.Deltas storage deltas = _market[dai].deltas;
        deltas.borrow.scaledTotalP2P = totalP2P;

        Types.Indexes256 memory indexes = _computeIndexes(dai);

        uint256 inP2P = _updateP2PDelta(dai, amount, indexes.borrow.p2pIndex, 0, deltas.borrow);

        uint256 expectedInP2P = amount.rayDiv(indexes.borrow.p2pIndex);
        uint256 expectedInTotalScaledP2P = totalP2P + expectedInP2P;

        assertEq(inP2P, expectedInP2P, "inP2P");
        assertEq(deltas.borrow.scaledTotalP2P, expectedInTotalScaledP2P, "totalScaledP2P");
    }

    function testRepayFee(
        uint256 amount,
        uint256 supplyDelta,
        uint256 borrowDelta,
        uint256 totalScaledP2PSupply,
        uint256 totalScaledP2PBorrow
    ) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);

        totalScaledP2PSupply = bound(totalScaledP2PSupply, 0, MAX_AMOUNT);
        totalScaledP2PBorrow = bound(totalScaledP2PBorrow, 0, MAX_AMOUNT);

        supplyDelta =
            bound(supplyDelta, 0, totalScaledP2PSupply.rayMul(indexes.supply.p2pIndex).rayDiv(indexes.supply.poolIndex));
        borrowDelta =
            bound(borrowDelta, 0, totalScaledP2PBorrow.rayMul(indexes.borrow.p2pIndex).rayDiv(indexes.borrow.poolIndex));

        Types.Deltas storage deltas = _market[dai].deltas;
        deltas.supply.scaledDeltaPool = supplyDelta;
        deltas.borrow.scaledDeltaPool = borrowDelta;
        deltas.supply.scaledTotalP2P = totalScaledP2PSupply;
        deltas.borrow.scaledTotalP2P = totalScaledP2PBorrow;

        uint256 toProcess = _repayFee(dai, amount, indexes);

        uint256 expectedFeeToRepay = Math.zeroFloorSub(
            totalScaledP2PBorrow.rayMul(indexes.borrow.p2pIndex),
            totalScaledP2PSupply.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
                supplyDelta.rayMul(indexes.supply.poolIndex)
            )
        );
        expectedFeeToRepay = Math.min(amount, expectedFeeToRepay);

        assertEq(toProcess, amount - expectedFeeToRepay, "toProcess");
        assertEq(
            deltas.borrow.scaledTotalP2P,
            totalScaledP2PBorrow - expectedFeeToRepay.rayDiv(indexes.borrow.p2pIndex),
            "totalScaledP2PBorrow"
        );

        assertEq(deltas.supply.scaledDeltaPool, supplyDelta, "supplyDelta");
        assertEq(deltas.borrow.scaledDeltaPool, borrowDelta, "borrowDelta");
        assertEq(deltas.supply.scaledTotalP2P, totalScaledP2PSupply, "totalScaledP2PSupply");
    }

    function handleSupplyCap(address underlying, uint256 amount) external returns (uint256) {
        return _handleSupplyCap(underlying, amount);
    }

    function testHandleSupplyCapZero(uint256 amount) public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        reserveConfig.setSupplyCap(0);
        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        uint256 toSupply = _handleSupplyCap(dai, amount);
        assertEq(toSupply, amount);
    }

    function testHandleSupplyCapAlreadyCapped(uint256 amount, uint256 supplyCap) public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        uint256 totalSupply = ERC20(_market[dai].aToken).totalSupply();
        uint256 decimals = reserveConfig.getDecimals();
        supplyCap = bound(supplyCap, 1, totalSupply / (10 ** decimals));
        amount = bound(amount, 0, MAX_AMOUNT);

        reserveConfig.setSupplyCap(supplyCap);
        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        assertEq(_market[dai].idleSupply, 0);

        // Expects underflow
        vm.expectRevert();
        uint256 toSupply = this.handleSupplyCap(dai, amount);
    }

    function testHandleSupplyCap(uint256 amount, uint256 supplyCap) public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        uint256 totalSupply = ERC20(_market[dai].aToken).totalSupply();
        uint256 decimals = reserveConfig.getDecimals();
        supplyCap = bound(supplyCap, totalSupply / (10 ** decimals) + 1, totalSupply * 2 / (10 ** decimals));
        uint256 supplyCapScaled = supplyCap * (10 ** decimals);
        amount = bound(amount, 0, supplyCapScaled);

        reserveConfig.setSupplyCap(supplyCap);
        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        uint256 toSupply = _handleSupplyCap(dai, amount);
        assertEq(
            _market[dai].idleSupply, supplyCapScaled < totalSupply + amount ? totalSupply + amount - supplyCapScaled : 0
        );
        assertEq(toSupply, supplyCapScaled < totalSupply + amount ? supplyCapScaled - totalSupply : amount);
    }

    function testWithdrawIdle(uint256 amount, uint256 idle, uint256 inP2P) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        idle = bound(idle, 0, MAX_AMOUNT);
        inP2P = bound(inP2P, 0, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);
        uint256 p2pSupplyIndex = indexes.supply.p2pIndex;

        _market[dai].idleSupply = idle;
        _withdrawIdle(_market[dai], amount, inP2P, p2pSupplyIndex);

        assertEq(_market[dai].idleSupply, idle - Math.min(Math.min(idle, amount), inP2P.rayMul(p2pSupplyIndex)));
    }

    function testBorrowIdle(uint256 amount, uint256 idle, uint256 inP2P) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        idle = bound(idle, 0, MAX_AMOUNT);
        inP2P = bound(inP2P, 0, MAX_AMOUNT);
        Types.Indexes256 memory indexes = _computeIndexes(dai);
        uint256 p2pBorrowIndex = indexes.borrow.p2pIndex;

        _market[dai].idleSupply = idle;
        (uint256 newAmount, uint256 newInP2P) = _borrowIdle(_market[dai], amount, inP2P, p2pBorrowIndex);

        assertEq(_market[dai].idleSupply, idle - Math.min(idle, amount));
        assertEq(newAmount, amount - Math.min(idle, amount));
        assertEq(newInP2P, inP2P + Math.min(idle, amount).rayDiv(p2pBorrowIndex));
    }
}
