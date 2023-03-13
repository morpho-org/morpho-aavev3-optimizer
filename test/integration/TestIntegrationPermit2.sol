// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IAllowanceTransfer, AllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import {PermitHash} from "@permit2/libraries/PermitHash.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";
import {SignatureExpired} from "@permit2/PermitErrors.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationPermit2 is IntegrationTest {
    using SafeTransferLib for ERC20;

    AllowanceTransfer internal constant PERMIT2 = AllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    function setUp() public override {
        super.setUp();
    }

    function getPermitHash(address underlying, address delegator, address spender, uint256 amount, uint256 deadline)
        internal
        view
        returns (bytes32 hashed)
    {
        (,, uint48 nonce) = PERMIT2.allowance(delegator, address(underlying), spender);
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(underlying),
            amount: SafeCast160.toUint160(amount),
            // Use an unlimited expiration because it most
            // closely mimics how a standard approval works.
            expiration: type(uint48).max,
            nonce: nonce
        });
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: spender, sigDeadline: deadline});

        hashed = PermitHash.hash(permitSingle);
        hashed = ECDSA.toTypedDataHash(PERMIT2.DOMAIN_SEPARATOR(), hashed);
    }

    function testSupplyWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount, uint256 seed) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);
        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        vm.prank(delegator);
        morpho.supplyWithPermit(market.underlying, amount, delegator, 10, deadline, sig);
        assertApproxEqAbs(morpho.supplyBalance(market.underlying, delegator), amount, 1, "Incorrect Supply");
    }

    function testSupplyCollateralWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount, uint256 seed)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, amount, delegator, deadline, sig);
        assertApproxEqAbs(
            morpho.collateralBalance(market.underlying, delegator), amount, 1, "Incorrect Supply Collateral"
        );
    }

    function testRepayWithPermit(uint256 privateKey, uint256 deadline, uint256 amount, uint256 seed) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        TestMarket storage market = testMarkets[_randomBorrowableUnderlying(seed)];

        amount = _boundBorrow(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        _borrowWithoutCollateral(address(delegator), market, amount, delegator, delegator, DEFAULT_MAX_ITERATIONS);

        uint256 balanceBefore = morpho.borrowBalance(market.underlying, delegator);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        vm.prank(delegator);
        morpho.repayWithPermit(market.underlying, amount, delegator, deadline, sig);

        assertApproxEqAbs(
            balanceBefore, morpho.borrowBalance(market.underlying, delegator) + amount, 1, "Incorrect Borrow Balance"
        );
    }

    function testRepayWithPermitShouldRevertBecauseDeadlinePassed(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max - 1);
        privateKey = bound(privateKey, 1, type(uint160).max);

        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        TestMarket storage market = testMarkets[_randomBorrowableUnderlying(seed)];

        amount = _boundBorrow(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);
        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        _borrowWithoutCollateral(address(delegator), market, amount, delegator, delegator, DEFAULT_MAX_ITERATIONS);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, amount);

        uint256 timestamp;
        timestamp = bound(timestamp, deadline + 1, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        vm.prank(delegator);
        morpho.repayWithPermit(market.underlying, amount, delegator, deadline, sig);
    }
}
