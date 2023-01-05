// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";

import {Test} from "@forge-std/Test.sol";
import {console2} from "@forge-std/console2.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";
import {DataTypes} from "../src/libraries/aave/DataTypes.sol";

import {MorphoInternal} from "../src/MorphoInternal.sol";
import {Types} from "../src/libraries/Types.sol";
import {MarketLib} from "../src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "../src/libraries/MarketBalanceLib.sol";
import {PoolLib} from "../src/libraries/PoolLib.sol";

contract TestMorphoInternal is MorphoInternal, Test {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using PoolLib for IPool;
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;

    uint256 internal constant positionMax = uint256(type(Types.PositionType).max);
    address internal dai;
    uint256 internal forkId;

    function setUp() public virtual {
        string memory network = vm.envString("NETWORK");
        string memory config = TestHelpers.getJsonConfig(network);

        forkId = TestHelpers.setForkFromJson(config);

        _addressesProvider =
            IPoolAddressesProvider(TestHelpers.getAddressFromJson(config, "LendingPoolAddressesProvider"));
        _pool = IPool(_addressesProvider.getPool());
        dai = TestHelpers.getAddressFromJson(config, "DAI");

        _defaultMaxLoops = Types.MaxLoops(10, 10, 10, 10);
        _maxSortedUsers = 20;

        createTestMarket(dai, 0, 3_333);
    }

    function createTestMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        DataTypes.ReserveData memory reserveData = _pool.getReserveData(underlying);

        Types.Market storage market = _market[underlying];

        Types.Indexes256 memory indexes;
        indexes.supply.p2pIndex = WadRayMath.RAY;
        indexes.borrow.p2pIndex = WadRayMath.RAY;
        (indexes.supply.poolIndex, indexes.borrow.poolIndex) = _pool.getCurrentPoolIndexes(underlying);

        market.setIndexes(indexes);
        market.lastUpdateTimestamp = uint32(block.timestamp);

        market.underlying = underlying;
        market.aToken = reserveData.aTokenAddress;
        market.variableDebtToken = reserveData.variableDebtTokenAddress;
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;

        _marketsCreated.push(underlying);

        ERC20(underlying).safeApprove(address(_pool), type(uint256).max);
    }

    function testDecodeId(uint256 id) public {
        vm.assume((id >> 252) <= positionMax);
        (address underlying, Types.PositionType positionType) = _decodeId(id);
        assertEq(underlying, address(uint160(id)));
        assertEq(uint256(positionType), id >> 252);
    }

    function testReverseDecodeId(address underlying, uint256 positionType) public {
        positionType = positionType % (positionMax + 1);
        uint256 id = uint256(uint160(underlying)) + (positionType << 252);
        (address decodedUnderlying, Types.PositionType decodedPositionType) = _decodeId(id);
        assertEq(decodedUnderlying, underlying);
        assertEq(uint256(decodedPositionType), positionType);
    }

    // More detailed index tests to be in InterestRatesLib tests
    function testComputeIndexes() public {
        address underlying = dai;
        Types.Indexes256 memory indexes1 = _market[underlying].getIndexes();
        Types.Indexes256 memory indexes2 = _computeIndexes(underlying);

        assertEq(indexes1.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertEq(indexes1.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertEq(indexes1.supply.poolIndex, indexes2.supply.poolIndex);
        assertEq(indexes1.borrow.poolIndex, indexes2.borrow.poolIndex);

        vm.warp(block.timestamp + 20);

        Types.Indexes256 memory indexes3 = _computeIndexes(underlying);

        assertGt(indexes3.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertGt(indexes3.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertGt(indexes3.supply.poolIndex, indexes2.supply.poolIndex);
        assertGt(indexes3.borrow.poolIndex, indexes2.borrow.poolIndex);
    }

    function testUpdateIndexes() public {
        address underlying = dai;
        Types.Indexes256 memory indexes1 = _market[underlying].getIndexes();
        _updateIndexes(underlying);
        Types.Indexes256 memory indexes2 = _market[underlying].getIndexes();

        assertEq(indexes1.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertEq(indexes1.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertEq(indexes1.supply.poolIndex, indexes2.supply.poolIndex);
        assertEq(indexes1.borrow.poolIndex, indexes2.borrow.poolIndex);

        vm.warp(block.timestamp + 20);

        _updateIndexes(underlying);
        Types.Indexes256 memory indexes3 = _market[underlying].getIndexes();

        assertGt(indexes3.supply.p2pIndex, indexes2.supply.p2pIndex);
        assertGt(indexes3.borrow.p2pIndex, indexes2.borrow.p2pIndex);
        assertGt(indexes3.supply.poolIndex, indexes2.supply.poolIndex);
        assertGt(indexes3.borrow.poolIndex, indexes2.borrow.poolIndex);
    }

    function testUpdateInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateInDS(address(0), user, marketBalances.poolSuppliers, marketBalances.p2pSuppliers, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateSupplierInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateSupplierInDS(dai, user, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), onPool);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), inP2P);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), 0);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), 0);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testUpdateBorrowerInDS(address user, uint96 onPool, uint96 inP2P) public {
        vm.assume(user != address(0));
        Types.MarketBalances storage marketBalances = _marketBalances[dai];
        _updateBorrowerInDS(dai, user, onPool, inP2P);
        assertEq(marketBalances.scaledPoolSupplyBalance(user), 0);
        assertEq(marketBalances.scaledP2PSupplyBalance(user), 0);
        assertEq(marketBalances.scaledPoolBorrowBalance(user), onPool);
        assertEq(marketBalances.scaledP2PBorrowBalance(user), inP2P);
        assertEq(marketBalances.scaledCollateralBalance(user), 0);
    }

    function testGetUserBalanceFromIndexes(uint96 onPool, uint96 inP2P, uint256 poolIndex, uint256 p2pIndex) public {
        poolIndex = bound(poolIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pIndex = bound(p2pIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);

        uint256 balance = _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolIndex, p2pIndex));

        assertEq(balance, uint256(onPool).rayMul(poolIndex) + uint256(inP2P).rayMul(p2pIndex));
    }

    function testGetUserSupplyBalanceFromIndexes(
        address user,
        uint96 onPool,
        uint96 inP2P,
        uint256 poolSupplyIndex,
        uint256 p2pSupplyIndex
    ) public {
        vm.assume(user != address(0));
        poolSupplyIndex = bound(poolSupplyIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pSupplyIndex = bound(p2pSupplyIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        _updateSupplierInDS(dai, user, onPool, inP2P);

        uint256 balance =
            _getUserSupplyBalanceFromIndexes(dai, user, Types.MarketSideIndexes256(poolSupplyIndex, p2pSupplyIndex));

        assertEq(
            balance,
            _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolSupplyIndex, p2pSupplyIndex))
        );
    }

    function testGetUserBorrowBalanceFromIndexes(
        address user,
        uint96 onPool,
        uint96 inP2P,
        uint256 poolBorrowIndex,
        uint256 p2pBorrowIndex
    ) public {
        vm.assume(user != address(0));
        poolBorrowIndex = bound(poolBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        p2pBorrowIndex = bound(p2pBorrowIndex, WadRayMath.RAY, 10 * WadRayMath.RAY);
        _updateBorrowerInDS(dai, user, onPool, inP2P);

        uint256 balance =
            _getUserBorrowBalanceFromIndexes(dai, user, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex));

        assertEq(
            balance,
            _getUserBalanceFromIndexes(onPool, inP2P, Types.MarketSideIndexes256(poolBorrowIndex, p2pBorrowIndex))
        );
    }

    /// TESTS TO ADD:

    // _assetLiquidityData
    // _liquidityDataCollateral
    // _liquidityDataDebt
    // _liquidityData

    // _setPauseStatus
}
