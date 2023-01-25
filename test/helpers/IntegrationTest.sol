// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";
import {IPositionsManager} from "src/interfaces/IPositionsManager.sol";

import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Morpho} from "src/Morpho.sol";
import {PositionsManager} from "src/PositionsManager.sol";
import {UserMock} from "test/mocks/UserMock.sol";
import "./ForkTest.sol";

contract IntegrationTest is ForkTest {
    using stdStorage for StdStorage;
    using Math for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 internal constant INITIAL_BALANCE = 10_000_000_000 ether;
    uint256 internal constant MIN_USD_AMOUNT = 0.0001e8; // AaveV3 base currency is USD, 8 decimals on all L2s.
    uint256 internal constant MAX_USD_AMOUNT = 500_000_000e8; // AaveV3 base currency is USD, 8 decimals on all L2s.

    IMorpho internal morpho;
    IPositionsManager internal positionsManager;

    ProxyAdmin internal proxyAdmin;

    IMorpho internal morphoImpl;
    TransparentUpgradeableProxy internal morphoProxy;

    UserMock internal user1;
    UserMock internal user2;
    UserMock internal promoter;

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
        uint256 minAmount;
        uint256 maxAmount;
    }

    TestMarket[] internal markets;
    TestMarket[] internal borrowableMarkets;
    TestMarket internal defaultCollateralMarket;

    function setUp() public virtual override {
        (defaultCollateralMarket,) = _initMarket(sAvax, 0, 0);

        _deploy();

        // Order should not be changed.
        _createMarket(weth, 0, 33_33);
        _createMarket(dai, 0, 33_33);
        _createMarket(usdc, 0, 33_33);
        _createMarket(usdt, 0, 33_33);
        _createMarket(wbtc, 0, 33_33);
        _createMarket(aave, 0, 33_33);
        _createMarket(link, 0, 33_33);
        _createMarket(wavax, 0, 33_33);

        _forward(1); // All markets are outdated in Morpho's storage.

        user1 = _initUser();
        user2 = _initUser();
        promoter = _initUser();

        super.setUp();
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
        positionsManager = new PositionsManager(address(addressesProvider), 0);
        morphoImpl = new Morpho(address(addressesProvider), 0);

        proxyAdmin = new ProxyAdmin();
        morphoProxy = new TransparentUpgradeableProxy(payable(address(morphoImpl)), address(proxyAdmin), "");
        morpho = Morpho(payable(address(morphoProxy)));

        morpho.initialize(address(positionsManager), Types.MaxLoops({repay: 10, withdraw: 10}));

        // Supply dust to make UserConfigurationMap.isUsingAsCollateralOne() always return true.
        _deposit(weth, 1e12, address(morpho));
        _deposit(dai, 1e12, address(morpho));

        // Disable supply cap on default collateral market to avoid reverts.
        poolAdmin.setSupplyCap(defaultCollateralMarket.underlying, 0);
    }

    function _initUser() internal returns (UserMock user) {
        user = new UserMock(address(morpho));

        _setBalances(address(user), INITIAL_BALANCE);
    }

    function _createForkFromEnv() internal {
        string memory endpoint = vm.envString("FOUNDRY_ETH_RPC_URL");
        uint256 blockNumber = vm.envUint("FOUNDRY_FORK_BLOCK_NUMBER");

        forkId = vm.createSelectFork(endpoint, blockNumber);
    }

    function _initMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor)
        internal
        returns (TestMarket memory market, DataTypes.ReserveData memory reserve)
    {
        reserve = pool.getReserveData(underlying);

        market.aToken = reserve.aTokenAddress;
        market.debtToken = reserve.variableDebtTokenAddress;
        market.underlying = underlying;
        market.symbol = ERC20(underlying).symbol();
        market.reserveFactor = reserveFactor;
        market.p2pIndexCursor = p2pIndexCursor;
        market.price = oracle.getAssetPrice(underlying); // Price is constant, equal to price at fork block number.

        (market.ltv, market.lt, market.liquidationBonus, market.decimals,,) = reserve.configuration.getParams();

        market.supplyCap = reserve.configuration.getSupplyCap() * 10 ** market.decimals;
        market.borrowCap = reserve.configuration.getBorrowCap() * 10 ** market.decimals;

        market.minAmount = (MIN_USD_AMOUNT * 10 ** market.decimals) / market.price;
        market.maxAmount = (MAX_USD_AMOUNT * 10 ** market.decimals) / market.price;

        vm.label(reserve.aTokenAddress, string.concat("a", market.symbol));
        vm.label(reserve.variableDebtTokenAddress, string.concat("d", market.symbol));
    }

    function _createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) internal {
        (TestMarket memory market, DataTypes.ReserveData memory reserve) =
            _initMarket(underlying, reserveFactor, p2pIndexCursor);

        markets.push(market);
        if (
            market.ltv > 0 && reserve.configuration.getBorrowingEnabled() && !reserve.configuration.getSiloedBorrowing()
                && !reserve.configuration.getBorrowableInIsolation() && market.borrowCap > 0
                && market.borrowCap > ERC20(market.debtToken).totalSupply()
        ) borrowableMarkets.push(market);

        morpho.createMarket(underlying, reserveFactor, p2pIndexCursor);
    }

    /// @dev Disables the same block borrow/repay limitation by resetting the previous index of Morpho on AaveV3.
    /// https://github.com/aave/aave-v3-core/blob/bb625723211944a7325b505caf6199edf4b8ed2a/contracts/protocol/tokenization/base/IncentivizedERC20.sol#L41-L50
    /// The check was removed in commit https://github.com/aave/aave-v3-core/commit/b1d94da8c4de795e94a7ff5c1429a98854cb2b65 but the change is not deployed at test block.
    function _resetPreviousIndex(TestMarket memory market) internal {
        bytes32 slot = keccak256(abi.encode(address(morpho), 56));
        vm.store(
            market.debtToken,
            slot,
            vm.load(market.debtToken, slot) & 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
        );
    }

    /// @dev Deposits the given amount of tokens on behalf of the given address, on AaveV3.
    function _deposit(address underlying, uint256 amount, address onBehalf) internal {
        deal(underlying, address(this), amount);
        ERC20(underlying).approve(address(pool), amount);
        pool.deposit(underlying, amount, onBehalf, 0);
    }

    /// @dev Calculates the underlying amount that can be supplied on the given market, reaching the supply cap.
    function _supplyGap(TestMarket memory market) internal view returns (uint256) {
        return
            market.supplyCap > 0 ? market.supplyCap.zeroFloorSub(ERC20(market.aToken).totalSupply()) : type(uint256).max;
    }

    /// @dev Calculates the underlying amount that can be supplied on the given market, reaching the borrow cap.
    function _borrowGap(TestMarket memory market) internal view returns (uint256) {
        return market.borrowCap > 0
            ? market.borrowCap.zeroFloorSub(ERC20(market.debtToken).totalSupply())
            : type(uint256).max;
    }

    /// @dev Bounds the input between the minimum & the maximum USD amount expected in tests, without exceeding the market's supply cap.
    function _boundSupply(TestMarket memory market, uint256 amount) internal view returns (uint256) {
        return bound(amount, market.minAmount, Math.min(market.maxAmount, _supplyGap(market)));
    }

    /// @dev Bounds the input between 0 and the maximum borrowable quantity, without exceeding the market's liquidity nor its borrow cap.
    function _boundBorrow(TestMarket memory market, uint256 amount) internal view returns (uint256) {
        return bound(
            amount,
            market.minAmount,
            Math.min(market.maxAmount, Math.min(ERC20(market.underlying).balanceOf(market.aToken), _borrowGap(market)))
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
            (amount * borrowedMarket.price * 10 ** collateralMarket.decimals).percentDiv(collateralMarket.ltv - 1)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        );
    }

    /// @dev Borrows from `user` on behalf of `onBehalf`, without collateral.
    function _borrowNoCollateral(
        address user,
        TestMarket memory market,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint256 maxLoops
    ) internal returns (uint256 borrowed) {
        oracle.setAssetPrice(market.underlying, 0);

        vm.prank(user);
        borrowed = morpho.borrow(market.underlying, amount, onBehalf, receiver, maxLoops);

        _deposit(weth, _minCollateral(markets[0], market, borrowed), address(morpho)); // Make Morpho solvent with WETH because no supply cap.

        oracle.setAssetPrice(market.underlying, market.price);
    }

    /// @dev Promotes the incoming (or already provided) supply, without collateral.
    function _promoteSupply(TestMarket memory market, uint256 amount) internal returns (uint256 borrowed) {
        borrowed = bound(amount, 0, Math.min(ERC20(market.underlying).balanceOf(market.aToken), _borrowGap(market)));

        oracle.setAssetPrice(market.underlying, 0);

        try promoter.borrow(market.underlying, borrowed) {
            _resetPreviousIndex(market); // Enable borrow/repay in same block.
            _deposit(
                defaultCollateralMarket.underlying,
                _minCollateral(defaultCollateralMarket, market, borrowed),
                address(morpho)
            ); // Make Morpho solvent with DAI, having the largest supply cap.
        } catch {
            borrowed = 0;
        }

        oracle.setAssetPrice(market.underlying, market.price);
    }

    /// @dev Promotes the incoming (or already provided) borrow.
    function _promoteBorrow(TestMarket memory market, uint256 amount) internal returns (uint256 supplied) {
        supplied = bound(amount, 0, _supplyGap(market));

        promoter.approve(market.underlying, supplied);
        promoter.supply(market.underlying, supplied);
    }
}
