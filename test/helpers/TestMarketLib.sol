// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Math} from "@morpho-utils/math/Math.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Vm} from "@forge-std/Vm.sol";

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

library TestMarketLib {
    using Math for uint256;
    using PercentageMath for uint256;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Disables the same block borrow/repay limitation by resetting the previous index of the given user on AaveV3.
    /// https://github.com/aave/aave-v3-core/blob/bb625723211944a7325b505caf6199edf4b8ed2a/contracts/protocol/tokenization/base/IncentivizedERC20.sol#L41-L50
    /// The check was removed in commit https://github.com/aave/aave-v3-core/commit/b1d94da8c4de795e94a7ff5c1429a98854cb2b65 but the change is not deployed at test block.
    function _resetPreviousIndex(address debtToken, address user) private {
        bytes32 slot = keccak256(abi.encode(user, 56));
        vm.store(
            debtToken,
            slot,
            vm.load(debtToken, slot) & 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
        );
    }

    function resetPreviousIndex(TestMarket storage market, address user) internal {
        _resetPreviousIndex(market.debtToken, user);
    }

    function totalSupply(TestMarket storage market) internal view returns (uint256) {
        return ERC20(market.aToken).totalSupply();
    }

    function totalBorrow(TestMarket storage market) internal view returns (uint256) {
        return ERC20(market.debtToken).totalSupply();
    }

    /// @dev Calculates the underlying amount that can be supplied on the given market on AaveV3, reaching the supply cap.
    function supplyGap(TestMarket storage market) internal view returns (uint256) {
        return market.supplyCap.zeroFloorSub(totalSupply(market));
    }

    /// @dev Calculates the underlying amount that can be supplied on the given market on AaveV3, reaching the borrow cap.
    function borrowGap(TestMarket storage market) internal view returns (uint256) {
        return market.borrowCap.zeroFloorSub(totalBorrow(market));
    }

    /// @dev Calculates the maximum borrowable quantity collateralized by the given quantity of collateral.
    function borrowable(TestMarket storage borrowedMarket, TestMarket storage collateralMarket, uint256 collateral)
        internal
        view
        returns (uint256)
    {
        return (
            (collateral * collateralMarket.price * 10 ** borrowedMarket.decimals).percentMul(collateralMarket.ltv - 1)
                / (borrowedMarket.price * 10 ** collateralMarket.decimals)
        );
    }

    /// @dev Calculates the minimum collateral quantity necessary to collateralize the given quantity of debt.
    function minCollateral(TestMarket storage collateralMarket, TestMarket storage borrowedMarket, uint256 amount)
        internal
        view
        returns (uint256)
    {
        return (
            (amount * borrowedMarket.price * 10 ** collateralMarket.decimals).percentDiv(collateralMarket.ltv - 1)
                / (collateralMarket.price * 10 ** borrowedMarket.decimals)
        );
    }
}
