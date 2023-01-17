// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IPositionsManager} from "../../src/interfaces/IPositionsManager.sol";
import {IMorpho} from "../../src/interfaces/IMorpho.sol";

import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TestUser} from "../helpers/TestUser.sol";

import {PositionsManager} from "../../src/PositionsManager.sol";
import {Morpho} from "../../src/Morpho.sol";

import "./ForkTest.sol";

contract IntegrationTest is ForkTest {
    using stdStorage for StdStorage;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant INITIAL_BALANCE = 10_000_000_000 ether;
    uint256 internal constant MIN_USD_AMOUNT = 0.001e8; // AaveV3 base currency is USD, 8 decimals on all L2s.
    uint256 internal constant MAX_USD_AMOUNT = 10_000_000_000e8; // AaveV3 base currency is USD, 8 decimals on all L2s.

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    TestUser internal user1;
    TestUser internal user2;
    TestUser internal promoter;

    struct TestMarket {
        address aToken;
        address debtToken;
        address underlying;
        string symbol;
        uint256 decimals;
        //
        uint256 ltv;
        uint256 lt;
        uint256 liquidationBonus;
        uint256 supplyCap;
        uint256 borrowCap;
        //
        uint16 reserveFactor;
        uint16 p2pIndexCursor;
        //
        uint256 price;
        uint256 totalSupply;
        uint256 totalBorrow;
    }

    TestMarket[] internal markets;
    TestMarket[] internal borrowableMarkets;

    function setUp() public virtual override {
        super.setUp();

        _deploy();

        _initMarket(weth, 0, 33_33);
        _initMarket(dai, 0, 33_33);
        _initMarket(usdc, 0, 33_33);
        _initMarket(usdt, 0, 33_33);
        _initMarket(aave, 0, 33_33);
        _initMarket(link, 0, 33_33);
        _initMarket(wavax, 0, 33_33);
        _initMarket(wbtc, 0, 33_33);

        user1 = _initUser();
        user2 = _initUser();
        promoter = _initUser();
    }

    function _label() internal override {
        super._label();

        vm.label(address(morpho), "Morpho");
        vm.label(address(morphoImpl), "MorphoImpl");
        vm.label(address(positionsManager), "PositionsManager");

        vm.label(address(user1), "User1");
        vm.label(address(user2), "User2");
        vm.label(address(promoter), "Promoter");
    }

    function _deploy() internal {
        positionsManager = new PositionsManager(address(addressesProvider));
        morphoImpl = new Morpho(address(addressesProvider));

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(
            address(positionsManager), Types.MaxLoops({supply: 10, borrow: 10, repay: 10, withdraw: 10}), 20
        );

        // Supply dust on WETH to make UserConfigurationMap.isUsingAsCollateralOne() always return true.
        deal(weth, address(this), 1e9);
        ERC20(weth).approve(address(pool), 1e9);
        pool.deposit(weth, 1e9, address(morpho), 0);
    }

    function _initUser() internal returns (TestUser user) {
        user = new TestUser(address(morpho));

        _setBalances(address(user), INITIAL_BALANCE);
    }

    function _createForkFromEnv() internal {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }

    function _initMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);

        TestMarket memory market;
        market.aToken = reserve.aTokenAddress;
        market.debtToken = reserve.variableDebtTokenAddress;
        market.underlying = underlying;
        market.symbol = ERC20(underlying).symbol();
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;
        market.price = oracle.getAssetPrice(underlying); // Price is constant, equal to price at fork block number.
        market.totalSupply = ERC20(reserve.aTokenAddress).totalSupply();
        market.totalBorrow = ERC20(reserve.variableDebtTokenAddress).totalSupply();

        (market.ltv, market.lt, market.liquidationBonus, market.decimals,,) = reserve.configuration.getParams();
        market.supplyCap = reserve.configuration.getSupplyCap() * 10 ** market.decimals;
        market.borrowCap = reserve.configuration.getBorrowCap() * 10 ** market.decimals;

        markets.push(market);
        if (
            market.ltv > 0 && reserve.configuration.getBorrowingEnabled() && !reserve.configuration.getSiloedBorrowing()
                && !reserve.configuration.getBorrowableInIsolation() && market.borrowCap > 0
                && market.borrowCap > market.totalBorrow
        ) borrowableMarkets.push(market);

        vm.label(reserve.aTokenAddress, string.concat("a", market.symbol));
        vm.label(reserve.variableDebtTokenAddress, string.concat("d", market.symbol));

        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    /// @dev Disables the same block borrow/repay limitation by resetting the previous index of Morpho on AaveV3.
    function _resetPreviousIndex(TestMarket memory market) internal {
        vm.store(market.debtToken, keccak256(abi.encode(address(morpho), 56)), 0);
    }

    /// @dev Bounds the input between the minimum & the maximum USD amount expected in tests, without exceeding the market's supply cap.
    function _boundSupply(TestMarket memory market, uint256 amount) internal view returns (uint256) {
        return bound(
            amount,
            (MIN_USD_AMOUNT * 10 ** market.decimals) / market.price,
            Math.min((MAX_USD_AMOUNT * 10 ** market.decimals) / market.price, market.supplyCap - market.totalSupply)
        );
    }

    /// @dev Bounds the input between 0 and the maximum borrowable quantity, without exceeding the market's liquidity nor its borrow cap.
    function _boundBorrow(TestMarket memory collateralMarket, TestMarket memory borrowedMarket, uint256 collateral)
        internal
        view
        returns (uint256)
    {
        return bound(
            collateral,
            0,
            Math.min(
                ERC20(borrowedMarket.underlying).balanceOf(borrowedMarket.aToken),
                Math.min(
                    _borrowable(collateralMarket, borrowedMarket, collateral),
                    borrowedMarket.borrowCap > 0
                        ? borrowedMarket.borrowCap - borrowedMarket.totalBorrow
                        : type(uint256).max
                )
            )
        );
    }

    /// @dev Calculates the maximum borrowable quantity collateralized by the given quantity of collateral.
    function _borrowable(TestMarket memory collateralMarket, TestMarket memory borrowedMarket, uint256 collateral)
        internal
        pure
        returns (uint256)
    {
        return (
            (collateral * collateralMarket.price * 10 ** borrowedMarket.decimals).percentMul(collateralMarket.ltv - 1)
                / (borrowedMarket.price * 10 ** collateralMarket.decimals)
        );
    }

    /// @dev Calculates the minimum collateral quantity necessary to collateralize the given quantity of debt.
    function _minCollateral(TestMarket memory collateralMarket, TestMarket memory borrowedMarket, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return (
            (amount * borrowedMarket.price * 10 ** collateralMarket.decimals).percentDiv(collateralMarket.ltv)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        );
    }

    /// @dev Makes the promoter supply up to 50% of the supply cap, then use a portion of their collateral power to borrow from the same market.
    /// @return supplied Always equal to the collateral supplied by the promoter.
    /// @return borrowed Equal to the debt borrowed by the promoter iff the market is borrowable.
    function _borrowUpTo(
        TestMarket memory collateralMarket,
        TestMarket memory borrowMarket,
        uint256 amount,
        uint256 utilizationBps
    ) internal returns (uint256 supplied, uint256 borrowed) {
        // Divided by 2 because will be supplied by promoter & promoted and may thus reach supply cap otherwise.
        supplied = _boundSupply(collateralMarket, amount) / 2;
        borrowed = _boundBorrow(collateralMarket, borrowMarket, supplied.percentMul(utilizationBps));

        promoter.approve(collateralMarket.underlying, supplied);
        promoter.supplyCollateral(collateralMarket.underlying, supplied);

        // Reverts if the market is not borrowable.
        try promoter.borrow(borrowMarket.underlying, borrowed) {} catch {}

        _resetPreviousIndex(borrowMarket);
    }
}
