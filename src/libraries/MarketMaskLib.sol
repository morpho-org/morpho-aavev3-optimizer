pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {Constants} from "./Constants.sol";

library MarketMaskLib {
    bytes32 internal constant BORROWING_MASK = Constants.BORROWING_MASK;

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function isSupplyingOrBorrowing(Types.UserMarkets memory userMarkets, Types.BorrowMask memory borrowMask)
        internal
        pure
        returns (bool)
    {
        return userMarkets.data & (borrowMask.data | (borrowMask.data << 1)) != 0;
    }

    /// @dev Returns if a user is borrowing on a given market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowMask The borrow mask of the market to check.
    /// @return True if the user has been borrowing on this market, false otherwise.
    function isBorrowing(Types.UserMarkets memory userMarkets, Types.BorrowMask memory borrowMask)
        internal
        pure
        returns (bool)
    {
        return userMarkets.data & borrowMask.data != 0;
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function isSupplying(Types.UserMarkets memory userMarkets, Types.BorrowMask memory borrowMask)
        internal
        pure
        returns (bool)
    {
        return userMarkets.data & (borrowMask.data << 1) != 0;
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function isBorrowingAny(Types.UserMarkets memory userMarkets) internal pure returns (bool) {
        return userMarkets.data & BORROWING_MASK != 0;
    }

    /// @dev Returns if a user is borrowing on a given market and supplying on another given market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowedBorrowMask The borrow mask of the market to check whether the user is borrowing.
    /// @param suppliedBorrowMask The borrow mask of the market to check whether the user is supplying.
    /// @return True if the user is borrowing on the given market and supplying on the other given market, false otherwise.
    function isBorrowingAndSupplying(
        Types.UserMarkets memory userMarkets,
        Types.BorrowMask memory borrowedBorrowMask,
        Types.BorrowMask memory suppliedBorrowMask
    ) internal pure returns (bool) {
        Types.BorrowMask memory combinedBorrowMask;
        combinedBorrowMask.data = borrowedBorrowMask.data | (suppliedBorrowMask.data << 1);
        return userMarkets.data & combinedBorrowMask.data == combinedBorrowMask.data;
    }

    /// @notice Sets if the user is borrowing on a market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowMask The borrow mask of the market to mark as borrowed.
    /// @param borrowing True if the user is borrowing, false otherwise.
    /// @return  The new user bitmask.
    function setBorrowing(Types.UserMarkets memory userMarkets, Types.BorrowMask memory borrowMask, bool borrowing)
        internal
        pure
        returns (Types.UserMarkets memory)
    {
        userMarkets.data = borrowing ? userMarkets.data | borrowMask.data : userMarkets.data & (~borrowMask.data);
        return userMarkets;
    }

    /// @notice Sets if the user is supplying on a market.
    /// @param userMarkets The bitmask encoding the markets entered by the user.
    /// @param borrowMask The borrow mask of the market to mark as supplied.
    /// @param supplying True if the user is supplying, false otherwise.
    /// @return  The new user bitmask.
    function setSupplying(Types.UserMarkets memory userMarkets, Types.BorrowMask memory borrowMask, bool supplying)
        internal
        pure
        returns (Types.UserMarkets memory)
    {
        userMarkets.data =
            supplying ? userMarkets.data | (borrowMask.data << 1) : userMarkets.data & (~(borrowMask.data << 1));
        return userMarkets;
    }
}
