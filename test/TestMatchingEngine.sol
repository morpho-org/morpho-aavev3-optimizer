// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {TestConfig} from "./helpers/TestConfig.sol";

import {TestSetup} from "./setup/TestSetup.sol";
import {console2} from "@forge-std/console2.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
import {ThreeHeapOrdering} from "@morpho-data-structures/ThreeHeapOrdering.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPool, IPoolAddressesProvider} from "../src/interfaces/aave/IPool.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "../src/libraries/aave/DataTypes.sol";
import {ReserveConfiguration} from "../src/libraries/aave/ReserveConfiguration.sol";

import {MatchingEngine} from "../src/MatchingEngine.sol";
import {MorphoInternal} from "../src/MorphoInternal.sol";
import {MorphoStorage} from "../src/MorphoStorage.sol";
import {Types} from "../src/libraries/Types.sol";
import {MarketLib} from "../src/libraries/MarketLib.sol";
import {MarketBalanceLib} from "../src/libraries/MarketBalanceLib.sol";
import {PoolLib} from "../src/libraries/PoolLib.sol";
import {Math} from "@morpho-utils/math/Math.sol";

contract TestMorphoInternal is TestSetup, MatchingEngine {
    using MarketLib for Types.Market;
    using MarketBalanceLib for Types.MarketBalances;
    using PoolLib for IPool;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using ThreeHeapOrdering for ThreeHeapOrdering.HeapArray;
    using TestConfig for TestConfig.Config;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    constructor() TestSetup() MorphoStorage(config.load(vm.envString("NETWORK")).getAddress("addressesProvider")) {}

    function setUp() public virtual override {
        _defaultMaxLoops = Types.MaxLoops(10, 10, 10, 10);
        _maxSortedUsers = 20;

        createMarket(dai);
        createMarket(wbtc);
        createMarket(usdc);
        createMarket(usdt);
        createMarket(wNative);
    }

    function testPromote(
        uint256 poolBalance,
        uint256 p2pBalance,
        uint256 poolIndex,
        uint256 p2pIndex,
        uint256 remaining
    ) public {
        poolBalance = bound(poolBalance, 0, type(uint96).max);
        p2pBalance = bound(p2pBalance, 0, type(uint96).max);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 1_000);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 1_000);
        remaining = bound(remaining, 0, type(uint96).max);

        uint256 toProcess = Math.min(poolBalance.rayMul(poolIndex), remaining);

        (uint256 newPoolBalance, uint256 newP2PBalance, uint256 newRemaining) =
            _promote(poolBalance, p2pBalance, Types.MarketSideIndexes256(poolIndex, p2pIndex), remaining);

        assertEq(newPoolBalance, poolBalance - toProcess.rayDiv(poolIndex));
        assertEq(newP2PBalance, p2pBalance + toProcess.rayDiv(p2pIndex));
        assertEq(newRemaining, remaining - toProcess);
    }
}
