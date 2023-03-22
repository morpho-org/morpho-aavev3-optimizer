// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";

import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";

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
    /// @return The current underlying price of the asset given Morpho's configuration
    function getUnderlyingPrice(DataTypes.ReserveConfigurationMap memory config, address underlying)
        public
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
            underlyingPrice = getUnderlyingPrice(config, underlying);
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

            underlyingPrice = getUnderlyingPrice(config, underlying);
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
        external
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
        external
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
        external
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
        external
        view
        returns (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance)
    {
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);
        balanceInP2P = morpho.scaledP2PBorrowBalance(underlying, user).rayMulUp(indexes.borrow.p2pIndex);
        balanceOnPool = morpho.scaledPoolBorrowBalance(underlying, user).rayMulUp(indexes.borrow.poolIndex);
        totalBalance = balanceInP2P + balanceOnPool;
    }
}
