// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {Types} from "../libraries/Types.sol";

interface IMorphoGetters {
    function maxSortedUsers() external view returns (uint256);
    function isClaimRewardsPaused() external view returns (bool);

    function POOL() external view returns (address);
    function ADDRESSES_PROVIDER() external view returns (address);
    function market(address underlying) external view returns (Types.Market memory);

    function scaledCollateralBalance(address underlying, address user) external view returns (uint256);
    function scaledP2PBorrowBalance(address underlying, address user) external view returns (uint256);
    function scaledP2PSupplyBalance(address underlying, address user) external view returns (uint256);
    function scaledPoolBorrowBalance(address underlying, address user) external view returns (uint256);
    function scaledPoolSupplyBalance(address underlying, address user) external view returns (uint256);
}

interface IMorphoSetters {
    function initialize(
        address newPositionsManager,
        Types.MaxLoops memory newDefaultMaxLoops,
        uint256 newMaxSortedUsers
    ) external;

    function createMarket(address underlying, uint16 reserveFactor, uint16 p2pIndexCursor) external;
    function increaseP2PDeltas(address underlying, uint256 amount) external;

    function setDefaultMaxLoops(Types.MaxLoops memory defaultMaxLoops) external;
    function setPositionsManager(address positionsManager) external;
    function setIsBorrowPaused(address underlying, bool isPaused) external;
    function setIsDeprecated(address underlying, bool isDeprecated) external;
    function setIsLiquidateBorrowPaused(address underlying, bool isPaused) external;
    function setIsLiquidateCollateralPaused(address underlying, bool isPaused) external;
    function setIsP2PDisabled(address underlying, bool isP2PDisabled) external;
    function setIsPaused(address underlying, bool isPaused) external;
    function setIsPausedForAllMarkets(bool isPaused) external;
    function setIsRepayPaused(address underlying, bool isPaused) external;
    function setIsSupplyPaused(address underlying, bool isPaused) external;
    function setIsWithdrawPaused(address underlying, bool isPaused) external;
    function setMaxSortedUsers(uint256 newMaxSortedUsers) external;
    function setP2PIndexCursor(address underlying, uint16 p2pIndexCursor) external;
    function setReserveFactor(address underlying, uint16 newReserveFactor) external;
}

interface IMorpho is IMorphoGetters, IMorphoSetters {
    function supply(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 supplied);
    function supplyCollateral(address underlying, uint256 amount, address onBehalf)
        external
        returns (uint256 supplied);

    function borrow(address underlying, uint256 amount, address receiver, uint256 maxLoops)
        external
        returns (uint256 borrowed);

    function repay(address underlying, uint256 amount, address onBehalf, uint256 maxLoops)
        external
        returns (uint256 repaid);

    function withdraw(address underlying, uint256 amount, address to, uint256 maxLoops)
        external
        returns (uint256 withdrawn);
    function withdrawCollateral(address underlying, uint256 amount, address to) external returns (uint256 withdrawn);

    function approveManager(address manager, bool isAllowed) external;

    function liquidate(address underlyingBorrowed, address underlyingCollateral, address user, uint256 amount)
        external
        returns (uint256 repaid, uint256 seized);
}
