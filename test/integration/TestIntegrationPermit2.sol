// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {PermitHash} from "@permit2/libraries/PermitHash.sol";
import {SignatureVerification} from "@permit2/libraries/SignatureVerification.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";
import {IAllowanceTransfer, AllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import {SignatureExpired} from "@permit2/PermitErrors.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationPermit2 is IntegrationTest {
    using SafeTransferLib for ERC20;

    AllowanceTransfer internal constant PERMIT2 = AllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

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

    function testSupplyWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount, uint256 seed, address onBehalf)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

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
        morpho.supplyWithPermit(market.underlying, amount, onBehalf, DEFAULT_MAX_ITERATIONS, deadline, sig);
        assertApproxEqAbs(morpho.supplyBalance(market.underlying, onBehalf), amount, 1, "Incorrect Supply");
        assertEq(ERC20(market.underlying).balanceOf(delegator), 0, "Incorrect Balance");
    }

    function testSupplyCollateralWithPermit2(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

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
        morpho.supplyCollateralWithPermit(market.underlying, amount, onBehalf, deadline, sig);
        assertApproxEqAbs(
            morpho.collateralBalance(market.underlying, onBehalf), amount, 1, "Incorrect Supply Collateral"
        );
        assertEq(ERC20(market.underlying).balanceOf(delegator), 0, "Incorrect Balance");
    }

    function testRepayWithPermit(uint256 privateKey, uint256 deadline, uint256 amount, uint256 seed, address onBehalf)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

        TestMarket storage market = testMarkets[_randomBorrowable(seed)];

        amount = _boundBorrow(market, amount);
        amount = Math.max(1, Math.min(type(uint160).max, amount));

        address spender = address(morpho);

        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        _borrowWithoutCollateral(onBehalf, market, amount, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        uint256 repaid = morpho.borrowBalance(market.underlying, onBehalf);
        _deal(market.underlying, delegator, repaid);
        vm.prank(delegator);
        morpho.repayWithPermit(market.underlying, repaid, onBehalf, deadline, sig);

        assertApproxEqAbs(morpho.borrowBalance(market.underlying, onBehalf), 0, 1, "Incorrect Borrow Balance");
        assertEq(ERC20(market.underlying).balanceOf(delegator), 0, "Incorrect Balance");
    }

    function testSupplyWithPermitShouldRevertBecauseDeadlinePassed(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max - 1);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

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
        timestamp = bound(timestamp, deadline + 1, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        vm.prank(delegator);
        morpho.supplyWithPermit(market.underlying, amount, onBehalf, DEFAULT_MAX_ITERATIONS, deadline, sig);
    }

    function testSupplyCollateralWithPermit2ShouldRevertIfSignatureUsedTwice(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashPermit);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, 2 * amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, amount, onBehalf, deadline, sig);

        vm.expectRevert(abi.encodeWithSelector(SignatureVerification.InvalidSigner.selector));
        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, amount, onBehalf, deadline, sig);
    }

    function testShouldRevertIfSomeoneImpersonateSignerOfPermit(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf,
        address pranker
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        vm.assume(pranker != delegator);
        onBehalf = _boundOnBehalf(onBehalf);

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

        vm.expectRevert(abi.encodeWithSelector(SignatureVerification.InvalidSigner.selector));
        vm.prank(pranker);
        morpho.supplyCollateralWithPermit(market.underlying, amount, onBehalf, deadline, sig);
    }

    function testShouldRevertIfSupplyAnotherAmountThanTheOneSigned(
        uint256 privateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf,
        uint256 supplied
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);
        supplied = bound(supplied, 0, amount - 1);

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

        vm.expectRevert(abi.encodeWithSelector(SignatureVerification.InvalidSigner.selector));
        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, supplied, onBehalf, deadline, sig);
    }

    function testShouldRevertIfPermitSignWithWrongPrivateKey(
        uint256 privateKey,
        uint256 wrongPrivateKey,
        uint256 deadline,
        uint256 amount,
        uint256 seed,
        address onBehalf
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        privateKey = bound(privateKey, 1, type(uint160).max);
        address delegator = vm.addr(privateKey);

        wrongPrivateKey = bound(wrongPrivateKey, 1, type(uint160).max);
        vm.assume(wrongPrivateKey != privateKey);

        onBehalf = _boundOnBehalf(onBehalf);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(market, amount);
        amount = Math.min(type(uint160).max, amount);

        address spender = address(morpho);

        bytes32 hashPermit = getPermitHash(market.underlying, delegator, spender, amount, deadline);

        Types.Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(wrongPrivateKey, hashPermit);

        vm.prank(delegator);
        ERC20(market.underlying).safeApprove(address(PERMIT2), amount);

        _deal(market.underlying, delegator, amount);

        uint256 timestamp;
        timestamp = bound(timestamp, 0, deadline - block.timestamp);
        vm.warp(block.timestamp + timestamp);

        vm.expectRevert(abi.encodeWithSelector(SignatureVerification.InvalidSigner.selector));
        vm.prank(delegator);
        morpho.supplyCollateralWithPermit(market.underlying, amount, onBehalf, deadline, sig);
    }
}
