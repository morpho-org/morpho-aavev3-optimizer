// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {AllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import "@permit2/libraries/PermitHash.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationPermit2 is IntegrationTest {
    using SafeTransferLib for ERC20;

    AllowanceTransfer internal constant PERMIT2 = AllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    function setUp() public override {
        super.setUp();
    }

    function testSupplyWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount) public {
        vm.assume(block.timestamp < deadline);
        privateKey = bound(privateKey, 1000, type(uint160).max);
        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        TestMarket storage market = testMarkets[underlyings[0]];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        (,, uint48 nonce) = PERMIT2.allowance(delegator, address(market.underlying), spender);
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(market.underlying),
            amount: SafeCast160.toUint160(amount),
            // Use an unlimited expiration because it most
            // closely mimics how a standard approval works.
            expiration: type(uint48).max,
            nonce: nonce
        });
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: spender, sigDeadline: deadline});

        bytes32 hashed = PermitHash.hash(permitSingle);
        hashed = keccak256(abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), hashed));

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        deal(market.underlying, delegator, amount);
        assertEq(ERC20(market.underlying).balanceOf(delegator), amount);

        vm.prank(delegator);
        morpho.supplyWithPermit(market.underlying, amount, delegator, 10, deadline, sig);
        assertApproxEqAbs(morpho.supplyBalance(market.underlying, delegator), amount, 1, "Incorrect Supply");
    }

    function testSupplyCollateralWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount) public {
        vm.assume(block.timestamp < deadline);
        privateKey = bound(privateKey, 1000, type(uint160).max);
        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        TestMarket storage market = testMarkets[underlyings[0]];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        (,, uint48 nonce) = PERMIT2.allowance(delegator, address(market.underlying), spender);
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(market.underlying),
            amount: SafeCast160.toUint160(amount),
            // Use an unlimited expiration because it most
            // closely mimics how a standard approval works.
            expiration: type(uint48).max,
            nonce: nonce
        });
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: spender, sigDeadline: deadline});

        bytes32 hashed = PermitHash.hash(permitSingle);
        hashed = keccak256(abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), hashed));

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        deal(market.underlying, delegator, amount);
        assertEq(ERC20(market.underlying).balanceOf(delegator), amount);

        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, amount, delegator, deadline, sig);
        assertApproxEqAbs(
            morpho.collateralBalance(market.underlying, delegator), amount, 1, "Incorrect Supply Collateral"
        );
    }

    function testRepayWithPermit(uint256 privateKey, uint256 deadline, uint256 amount) public {
        vm.assume(block.timestamp < deadline);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        TestMarket storage market = testMarkets[underlyings[0]];

        amount = _boundBorrow(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        (,, uint48 nonce) = PERMIT2.allowance(delegator, address(market.underlying), spender);
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(market.underlying),
            amount: SafeCast160.toUint160(amount),
            // Use an unlimited expiration because it most
            // closely mimics how a standard approval works.
            expiration: type(uint48).max,
            nonce: nonce
        });
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: spender, sigDeadline: deadline});

        bytes32 hashed =
            keccak256(abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), PermitHash.hash(permitSingle)));
        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);

        _borrowWithoutCollateral(address(delegator), market, amount, delegator, delegator, DEFAULT_MAX_ITERATIONS);

        uint256 balanceBefore = morpho.borrowBalance(market.underlying, delegator);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        deal(market.underlying, delegator, amount);
        assertEq(ERC20(market.underlying).balanceOf(delegator), amount);

        vm.prank(delegator);
        morpho.repayWithPermit(market.underlying, amount, delegator, deadline, sig);

        assertApproxEqAbs(
            balanceBefore, morpho.borrowBalance(market.underlying, delegator) + amount, 1, "Incorrect Borrow Balance"
        );
    }
}
