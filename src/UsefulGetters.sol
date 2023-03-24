// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import {IReserveInterestRateStrategy} from "@aave-v3-core/interfaces/IReserveInterestRateStrategy.sol";
import {IStableDebtToken} from "@aave-v3-core/interfaces/IStableDebtToken.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IMorpho} from "./interfaces/IMorpho.sol";
import {Types} from "./libraries/Types.sol";

/// @title Code Snippet Morpho-Aave V3
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Contract managing Aave's protocol rewards.
contract Snippet {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IMorpho public immutable morpho;
    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    uint8 public eModeCategoryId;

    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        pool = IPool(morpho.pool());
        addressesProvider = IPoolAddressesProvider(morpho.addressesProvider());
        eModeCategoryId = uint8(morpho.eModeCategoryId());
    }

    /// @notice Computes and return the price of an asset for Morpho User.
    /// @param config The configuration of the Morpho's user on Aave.
    /// @param underlying The address of the underlying asset to get the Price.
    /// @return underlyingPrice The current underlying price of the asset given Morpho's configuration
    function _getUnderlyingPrice(DataTypes.ReserveConfigurationMap memory config, address underlying)
        internal
        view
        returns (uint256 underlyingPrice)
    {
        IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
        DataTypes.EModeCategory memory categoryEModeData = pool.getEModeCategoryData(eModeCategoryId);

        bool isInEMode = eModeCategoryId != 0 && config.getEModeCategory() == eModeCategoryId;

        if (isInEMode && categoryEModeData.priceSource != address(0)) {
            underlyingPrice = oracle.getAssetPrice(categoryEModeData.priceSource);
            if (underlyingPrice != 0) oracle.getAssetPrice(underlying);
        } else {
            underlyingPrice = oracle.getAssetPrice(underlying);
        }
    }

    /// @notice Computes and returns the total distribution of supply through Morpho, using virtually updated indexes.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta and the idle supply on Morpho's contract (in USD).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in USD).
    /// @return idleSupplyAmount The total idle supply amount on the Morpho's contract (in USD).
    /// @return totalSupplyAmount The total amount supplied through Morpho.
    function getTotalSupply()
        external
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount)
    {
        address[] memory marketAddresses = morpho.marketsCreated();

        uint256 underlyingPrice;
        uint256 nbMarkets = marketAddresses.length;

        for (uint256 i; i < nbMarkets;) {
            address underlying = marketAddresses[i];

            Types.Market memory market = morpho.market(underlying);
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);

            uint256 marketPoolSupplyAmount = IAToken(market.aToken).balanceOf(address(morpho));
            underlyingPrice = _getUnderlyingPrice(config, underlying);
            Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

            uint256 assetUnit = 10 ** config.getDecimals();
            uint256 marketP2PSupplyAmount = market.deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex)
                .zeroFloorSub(market.deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)).zeroFloorSub(
                market.idleSupply
            );
            p2pSupplyAmount += (marketP2PSupplyAmount * underlyingPrice) / assetUnit;
            poolSupplyAmount += (marketPoolSupplyAmount * underlyingPrice) / assetUnit;
            idleSupplyAmount += (market.idleSupply * underlyingPrice) / assetUnit;

            unchecked {
                ++i;
            }
        }
        totalSupplyAmount = p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount;
    }

    /// @notice Computes and returns the total distribution of borrows through Morpho, using virtually updated indexes.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in USD).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in USD).
    /// @return totalBorrowAmount The total amount borrowed through Morpho (in USD).
    function getTotalBorrow()
        external
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount)
    {
        address[] memory marketAddresses = morpho.marketsCreated();

        uint256 underlyingPrice;
        uint256 nbMarkets = marketAddresses.length;

        for (uint256 i; i < nbMarkets;) {
            address underlying = marketAddresses[i];

            Types.Market memory market = morpho.market(underlying);
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);

            uint256 marketPoolBorrowAmount = ERC20(market.variableDebtToken).balanceOf(address(morpho));

            underlyingPrice = _getUnderlyingPrice(config, underlying);
            Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

            uint256 assetUnit = 10 ** config.getDecimals();
            uint256 marketP2PBorrowAmount = market.deltas.borrow.scaledP2PTotal.rayMul(indexes.borrow.p2pIndex)
                .zeroFloorSub(market.deltas.borrow.scaledDelta.rayMul(indexes.borrow.poolIndex));
            p2pBorrowAmount += (marketP2PBorrowAmount * underlyingPrice) / assetUnit;
            poolBorrowAmount += (marketPoolBorrowAmount * underlyingPrice) / assetUnit;

            unchecked {
                ++i;
            }
        }

        totalBorrowAmount = p2pBorrowAmount + poolBorrowAmount;
    }

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying) and the idle supply (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    /// @return idleSupplyAmount The total idle amount on the morpho's contract.
    function getTotalMarketSupply(address underlying)
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount)
    {
        Types.Market memory market = morpho.market(underlying);

        poolSupplyAmount = IAToken(market.aToken).balanceOf(address(morpho));
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pSupplyAmount = market.deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
            market.deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)
        ).zeroFloorSub(market.idleSupply);
        idleSupplyAmount = market.idleSupply;
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getTotalMarketBorrow(address underlying)
        public
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount)
    {
        Types.Market memory market = morpho.market(underlying);

        poolBorrowAmount = ERC20(market.variableDebtToken).balanceOf(address(morpho));
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pBorrowAmount = market.deltas.borrow.scaledP2PTotal.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            market.deltas.borrow.scaledDelta.rayMul(indexes.borrow.poolIndex)
        );
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentSupplyBalanceInOf(address underlying, address user)
        public
        view
        returns (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance)
    {
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);
        balanceInP2P = morpho.scaledP2PSupplyBalance(underlying, user).rayMulDown(indexes.supply.p2pIndex);
        balanceOnPool = morpho.scaledPoolSupplyBalance(underlying, user).rayMulDown(indexes.supply.poolIndex);
        totalBalance = balanceInP2P + balanceOnPool;
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentBorrowBalanceInOf(address underlying, address user)
        public
        view
        returns (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance)
    {
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);
        balanceInP2P = morpho.scaledP2PBorrowBalance(underlying, user).rayMulUp(indexes.borrow.p2pIndex);
        balanceOnPool = morpho.scaledPoolBorrowBalance(underlying, user).rayMulUp(indexes.borrow.poolIndex);
        totalBalance = balanceInP2P + balanceOnPool;
    }

    struct P2PRateComputeParams {
        uint256 poolSupplyRatePerYear;
        uint256 poolBorrowRatePerYear;
        uint256 poolIndex;
        uint256 p2pIndex;
        uint256 proportionIdle;
        uint256 p2pDelta;
        uint256 p2pAmount;
        uint256 p2pIndexCursor;
        uint256 reserveFactor;
    }

    /// @notice Returns the proportion of idle supply in `market` over the total peer-to-peer amount in supply.
    function getProportionIdle(Types.Market memory market) internal pure returns (uint256) {
        uint256 idleSupply = market.idleSupply;
        if (idleSupply == 0) return 0;

        uint256 totalP2PSupplied = market.deltas.supply.scaledP2PTotal.rayMul(market.indexes.supply.p2pIndex);
        return idleSupply.rayDivUp(totalP2PSupplied);
    }

    /// @notice Returns the supply rate per year a given user is currently experiencing on a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to compute the supply rate per year for.
    /// @return supplyRatePerYear The supply rate per year the user is currently experiencing (in wad).
    function getCurrentUserSupplyRatePerYear(address underlying, address user)
        external
        view
        returns (uint256 supplyRatePerYear)
    {
        (uint256 balanceInP2P, uint256 balanceOnPool,) = getCurrentSupplyBalanceInOf(underlying, user);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = _getPoolRatesPerYear(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pSupplyRate = computeP2PSupplyRatePerYear(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: getProportionIdle(market),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pAmount: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        (supplyRatePerYear,) = _getWeightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, balanceOnPool);
    }

    /// @notice Returns the borrow rate per year a given user is currently experiencing on a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to compute the borrow rate per year for.
    /// @return borrowRatePerYear The borrow rate per year the user is currently experiencing (in wad).
    function getCurrentUserBorrowRatePerYear(address underlying, address user)
        external
        view
        returns (uint256 borrowRatePerYear)
    {
        (uint256 balanceInP2P, uint256 balanceOnPool,) = getCurrentBorrowBalanceInOf(underlying, user);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = _getPoolRatesPerYear(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pBorrowRate = computeP2PBorrowRatePerYear(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pAmount: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        (borrowRatePerYear,) = _getWeightedRate(p2pBorrowRate, poolBorrowRate, balanceInP2P, balanceOnPool);
    }

    /// @dev Computes and returns the underlying pool rates for a specific market.
    /// @param underlying The underlying pool market address.
    /// @return poolSupplyRatePerYear The market's pool supply rate per year (in ray).
    /// @return poolBorrowRatePerYear The market's pool borrow rate per year (in ray).
    function _getPoolRatesPerYear(address underlying)
        internal
        view
        returns (uint256 poolSupplyRatePerYear, uint256 poolBorrowRatePerYear)
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
        poolSupplyRatePerYear = reserve.currentLiquidityRate;
        poolBorrowRatePerYear = reserve.currentVariableBorrowRate;
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
    function computeP2PSupplyRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate)
    {
        if (_params.poolSupplyRatePerYear > _params.poolBorrowRatePerYear) {
            p2pSupplyRate = _params.poolBorrowRatePerYear; // The p2pSupplyRate is set to the poolBorrowRatePerYear because there is no rate spread.
        } else {
            uint256 p2pRate = PercentageMath.weightedAvg(
                _params.poolSupplyRatePerYear, _params.poolBorrowRatePerYear, _params.p2pIndexCursor
            );

            p2pSupplyRate = p2pRate - (p2pRate - _params.poolSupplyRatePerYear).percentMul(_params.reserveFactor);
        }

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 proportionDelta = Math.min(
                _params.p2pDelta.rayMul(_params.poolIndex).rayDiv(_params.p2pAmount.rayMul(_params.p2pIndex)), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY - _params.proportionIdle // To avoid proportionDelta > 1 - proportionIdle with rounding errors.
            ); // In ray.

            p2pSupplyRate = p2pSupplyRate.rayMul(WadRayMath.RAY - proportionDelta - _params.proportionIdle)
                + _params.poolSupplyRatePerYear.rayMul(proportionDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per year (in ray).
    function computeP2PBorrowRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate)
    {
        if (_params.poolSupplyRatePerYear > _params.poolBorrowRatePerYear) {
            p2pBorrowRate = _params.poolBorrowRatePerYear; // The p2pBorrowRate is set to the poolBorrowRatePerYear because there is no rate spread.
        } else {
            uint256 p2pRate = PercentageMath.weightedAvg(
                _params.poolSupplyRatePerYear, _params.poolBorrowRatePerYear, _params.p2pIndexCursor
            );

            p2pBorrowRate = p2pRate - (_params.poolBorrowRatePerYear - p2pRate).percentMul(_params.reserveFactor);
        }

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 proportionDelta = Math.min(
                _params.p2pDelta.rayMul(_params.poolIndex).rayDiv(_params.p2pAmount.rayMul(_params.p2pIndex)), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid proportionDelta > 1 with rounding errors.
            ); // In ray.

            p2pBorrowRate = p2pBorrowRate.rayMul(WadRayMath.RAY - proportionDelta)
                + _params.poolBorrowRatePerYear.rayMul(proportionDelta);
        }
    }

    /// @dev Returns the rate experienced based on a given pool & peer-to-peer distribution.
    /// @param _p2pRate The peer-to-peer rate (in a unit common to `_poolRate` & `weightedRate`).
    /// @param _poolRate The pool rate (in a unit common to `_p2pRate` & `weightedRate`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @return weightedRate The rate experienced by the given distribution (in a unit common to `_p2pRate` & `_poolRate`).
    /// @return totalBalance The sum of peer-to-peer & pool balances.
    function _getWeightedRate(uint256 _p2pRate, uint256 _poolRate, uint256 _balanceInP2P, uint256 _balanceOnPool)
        internal
        pure
        returns (uint256 weightedRate, uint256 totalBalance)
    {
        totalBalance = _balanceInP2P + _balanceOnPool;
        if (totalBalance == 0) return (weightedRate, totalBalance);

        if (_balanceInP2P > 0) weightedRate += _p2pRate.rayMul(_balanceInP2P.rayDiv(totalBalance));
        if (_balanceOnPool > 0) {
            weightedRate += _poolRate.rayMul(_balanceOnPool.rayDiv(totalBalance));
        }
    }

    /// @notice Computes and returns the current supply rate per year experienced on average on a given market.
    /// @param underlying The address of the underlying asset.
    /// @return avgSupplyRatePerYear The market's average supply rate per year (in ray).
    /// @return avgBorrowRatePerYear The market's average borrow rate per year (in ray).
    function getAverageRatesPerYear(address underlying)
        public
        view
        returns (uint256 avgSupplyRatePerYear, uint256 avgBorrowRatePerYear)
    {
        Types.Market memory market = morpho.market(underlying);

        (uint256 poolSupplyRatePerYear, uint256 poolBorrowRatePerYear) = _getPoolRatesPerYear(underlying);

        uint256 p2pSupplyRatePerYear = computeP2PSupplyRatePerYear(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRatePerYear,
                poolBorrowRatePerYear: poolBorrowRatePerYear,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: getProportionIdle(market),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pAmount: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        (avgSupplyRatePerYear,) = _getWeightedRate(
            p2pSupplyRatePerYear,
            poolSupplyRatePerYear,
            market.deltas.supply.scaledP2PTotal.rayMul(market.indexes.supply.p2pIndex),
            IAToken(market.aToken).balanceOf(address(morpho)).zeroFloorSub(
                market.deltas.supply.scaledDelta.rayMul(market.indexes.supply.poolIndex)
            )
        );

        uint256 p2pBorrowRatePerYear = computeP2PBorrowRatePerYear(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRatePerYear,
                poolBorrowRatePerYear: poolBorrowRatePerYear,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pAmount: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        (avgBorrowRatePerYear,) = _getWeightedRate(
            p2pBorrowRatePerYear,
            poolBorrowRatePerYear,
            market.deltas.borrow.scaledP2PTotal.rayMul(market.indexes.borrow.p2pIndex),
            ERC20(market.variableDebtToken).balanceOf(address(morpho)).zeroFloorSub(
                market.deltas.borrow.scaledDelta.rayMul(market.indexes.borrow.poolIndex)
            )
        );
    }

    /// @notice Returns the health factor of a given user, using virtually updated pool & peer-to-peer indexes for all markets.
    /// @param user The user of whom to get the health factor.
    /// @return healthFactor The health factor of the given user (in wad).
    function getUserHealthFactor(address user) public view returns (uint256 healthFactor) {
        address[] memory collateralAddresses = morpho.userCollaterals(user);
        address[] memory borrowAddresses = morpho.userBorrows(user);

        uint256 collateralAmount;
        uint256 borrowAmount;
        uint256 maxDebt;
        uint256 debt;

        for (uint256 i = 0; i < collateralAddresses.length; ++i) {
            collateralAmount = morpho.supplyBalance(collateralAddresses[i], user);
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(collateralAddresses[i]);
            uint256 underlyingPrice = _getUnderlyingPrice(config, collateralAddresses[i]);

            uint256 assetUnit = 10 ** config.getDecimals();
            uint256 liquidationThreshold = config.getLiquidationThreshold();

            maxDebt += ((collateralAmount * underlyingPrice).percentMulDown(liquidationThreshold)) / assetUnit;
        }

        for (uint256 i = 0; i < borrowAddresses.length; ++i) {
            borrowAmount = morpho.supplyBalance(borrowAddresses[i], user);
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(borrowAddresses[i]);
            uint256 underlyingPrice = _getUnderlyingPrice(config, borrowAddresses[i]);

            uint256 assetUnit = 10 ** config.getDecimals();

            debt += (borrowAmount * underlyingPrice).divUp(assetUnit);
        }

        healthFactor = debt > 0 ? maxDebt.wadDiv(debt) : type(uint256).max;
    }
}
