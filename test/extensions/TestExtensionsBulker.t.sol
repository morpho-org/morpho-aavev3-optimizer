// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {PermitHash} from "@permit2/libraries/PermitHash.sol";
import {IAllowanceTransfer, AllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";
import {Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BulkerGateway} from "src/extensions/BulkerGateway.sol";
import {IBulkerGateway} from "src/interfaces/IBulkerGateway.sol";
import {ILido} from "src/interfaces/ILido.sol";
import {IWSTETH} from "src/interfaces/IWSTETH.sol";

import {SigUtils} from "test/helpers/SigUtils.sol";

import "test/helpers/IntegrationTest.sol";

contract TestExtensionsBulker is IntegrationTest {
    using SafeTransferLib for ERC20;

    AllowanceTransfer internal constant PERMIT2 = AllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    SigUtils internal sigUtils;
    IBulkerGateway internal bulker;
    address stETH;

    function setUp() public virtual override {
        super.setUp();
        bulker = new BulkerGateway(address(morpho));
        sigUtils = new SigUtils(morpho.DOMAIN_SEPARATOR());
        stETH = bulker.stETH();
    }

    function testShouldNotDeployWithMorphoZeroAddress() public {
        vm.expectRevert(IBulkerGateway.AddressIsZero.selector);
        new BulkerGateway(address(0));
    }

    function testShouldApproveAfterDeploy() public {
        assertEq(ERC20(bulker.WETH()).allowance(address(bulker), address(morpho)), type(uint256).max);
        assertEq(ERC20(bulker.stETH()).allowance(address(bulker), bulker.wstETH()), type(uint256).max);
        assertEq(ERC20(bulker.wstETH()).allowance(address(bulker), address(morpho)), type(uint256).max);
    }

    function testShouldApprove(uint256 seed, uint160 amount, uint256 privateKey) public {
        privateKey = bound(privateKey, 1, type(uint160).max);
        amount = uint160(bound(amount, 1, type(uint160).max));
        TestMarket memory market = testMarkets[_randomUnderlying(seed)];
        address delegator = vm.addr(privateKey);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);
        (actions[0], data[0]) =
            _getApproveData(privateKey, market.underlying, amount, type(uint48).max, IBulkerGateway.OpType.RAW);

        vm.prank(delegator);
        bulker.execute(actions, data);

        (uint160 allowance, uint48 newDeadline,) = PERMIT2.allowance(delegator, market.underlying, address(bulker));
        assertEq(allowance, amount, "allowance");
        assertEq(newDeadline, type(uint48).max, "deadline");
    }

    function testShouldTransferFrom(uint256 seed, uint256 amount, uint256 privateKey) public {
        privateKey = bound(privateKey, 1, type(uint160).max);
        amount = bound(amount, 1, type(uint160).max);
        TestMarket memory market = testMarkets[_randomUnderlying(seed)];
        address delegator = vm.addr(privateKey);
        deal(market.underlying, delegator, amount);

        vm.startPrank(delegator);
        ERC20(market.underlying).safeApprove(address(Permit2Lib.PERMIT2), 0);
        ERC20(market.underlying).safeApprove(address(Permit2Lib.PERMIT2), type(uint256).max);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](2);
        bytes[] memory data = new bytes[](2);
        (actions[0], data[0]) =
            _getApproveData(privateKey, market.underlying, uint160(amount), type(uint48).max, IBulkerGateway.OpType.RAW);
        (actions[1], data[1]) = _getTransferFromData(market.underlying, amount, IBulkerGateway.OpType.RAW);

        bulker.execute(actions, data);

        assertEq(ERC20(market.underlying).balanceOf(address(bulker)), amount, "bulker balance");
    }

    function testShouldWrapETH(address delegator, uint256 amount) public {
        amount = bound(amount, 1, type(uint160).max);
        deal(delegator, type(uint256).max);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getWrapETHData(amount, IBulkerGateway.OpType.RAW);

        vm.prank(delegator);
        bulker.execute{value: amount}(actions, data);
        assertEq(ERC20(bulker.WETH()).balanceOf(address(bulker)), amount, "bulker balance");
    }

    function testShouldUnwrapETH(address delegator, uint256 amount, address receiver) public {
        vm.assume(!Address.isContract(receiver));
        amount = bound(amount, 1, type(uint160).max);
        deal(wNative, amount);
        deal(wNative, address(bulker), amount);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getUnwrapETHData(amount, receiver, IBulkerGateway.OpType.RAW);

        uint256 balanceBefore = receiver.balance;

        vm.prank(delegator);
        bulker.execute(actions, data);

        assertEq(ERC20(bulker.WETH()).balanceOf(address(bulker)), 0, "bulker balance");
        assertEq(receiver.balance, balanceBefore + amount, "receiver balance");
    }

    function testShouldWrapStETH(address delegator, uint256 amount) public {
        vm.assume(delegator != address(0));
        amount = bound(amount, 1, ILido(stETH).getCurrentStakeLimit());
        deal(delegator, type(uint256).max);

        vm.startPrank(delegator);
        ILido(stETH).submit{value: amount}(address(0));
        ERC20(stETH).transfer(address(bulker), amount);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getWrapStETHData(amount, IBulkerGateway.OpType.RAW);

        bulker.execute(actions, data);
        assertEq(ERC20(sNative).balanceOf(address(bulker)), IWSTETH(sNative).getWstETHByStETH(amount), "bulker balance");
    }

    function testShouldUnwrapStETH(address delegator, uint256 amount, address receiver) public {
        vm.assume(delegator != address(0) && receiver != address(0));
        amount = bound(amount, 1, IWSTETH(sNative).totalSupply());
        deal(sNative, address(bulker), amount);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) = _getUnwrapStETHData(amount, receiver, IBulkerGateway.OpType.RAW);

        uint256 expectedBalance = ERC20(stETH).balanceOf(receiver) + IWSTETH(sNative).getStETHByWstETH(amount);

        vm.prank(delegator);
        bulker.execute(actions, data);

        // Rounding because stETH is rebasing and therefore can have rounding errors on transfer.
        assertApproxEqAbs(ERC20(stETH).balanceOf(receiver), expectedBalance, 2, "bulker balance");
    }

    function testShouldSupply(uint256 seed, address delegator, uint256 amount, address onBehalf, uint256 maxIterations)
        public
    {
        vm.assume(onBehalf != address(0));
        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        maxIterations = bound(maxIterations, 1, 10);
        amount = _boundSupply(market, amount);

        deal(market.underlying, address(bulker), amount);

        IBulkerGateway.ActionType[] memory actions = new IBulkerGateway.ActionType[](1);
        bytes[] memory data = new bytes[](1);

        (actions[0], data[0]) =
            _getSupplyData(market.underlying, amount, onBehalf, maxIterations, IBulkerGateway.OpType.RAW);

        vm.startPrank(delegator);
        bulker.execute(actions, data);

        assertEq(ERC20(market.underlying).balanceOf(address(bulker)), 0, "bulker balance");
        assertApproxEqAbs(morpho.supplyBalance(market.underlying, onBehalf), amount, 2, "onBehalf balance");
    }

    function _getApproveData(
        uint256 privateKey,
        address underlying,
        uint160 amount,
        uint48 deadline,
        IBulkerGateway.OpType op
    ) internal view returns (IBulkerGateway.ActionType action, bytes memory data) {
        address delegator = vm.addr(privateKey);
        action = IBulkerGateway.ActionType.APPROVE2;

        (,, uint48 nonce) = PERMIT2.allowance(delegator, underlying, address(bulker));
        IAllowanceTransfer.PermitDetails memory details =
            IAllowanceTransfer.PermitDetails({token: underlying, amount: amount, expiration: deadline, nonce: nonce});
        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle({details: details, spender: address(bulker), sigDeadline: deadline});

        Types.Signature memory sig;

        bytes32 hashed = PermitHash.hash(permitSingle);
        hashed = ECDSA.toTypedDataHash(PERMIT2.DOMAIN_SEPARATOR(), hashed);

        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);
        data = abi.encode(underlying, amount, deadline, sig, op);
    }

    function _getTransferFromData(address asset, uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.TRANSFER_FROM2;
        data = abi.encode(asset, amount, op);
    }

    function _getApproveManagerData(uint256 privateKey, bool isAllowed, uint256 deadline)
        internal
        view
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        address delegator = vm.addr(privateKey);
        action = IBulkerGateway.ActionType.APPROVE_MANAGER;

        uint256 nonce = morpho.userNonce(delegator);
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            delegator: delegator,
            manager: address(bulker),
            isAllowed: isAllowed,
            nonce: nonce,
            deadline: deadline
        });

        bytes32 hashed = sigUtils.getTypedDataHash(authorization);

        Types.Signature memory sig;

        (sig.v, sig.r, sig.s) = vm.sign(privateKey, hashed);
        data = abi.encode(isAllowed, nonce, deadline, sig);
    }

    function _getSupplyData(
        address asset,
        uint256 amount,
        address onBehalf,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.SUPPLY;
        data = abi.encode(asset, amount, onBehalf, maxIterations, op);
    }

    function _getSupplyCollateralData(address asset, uint256 amount, address onBehalf, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.SUPPLY_COLLATERAL;
        data = abi.encode(asset, amount, onBehalf, op);
    }

    function _getBorrowData(
        address asset,
        uint256 amount,
        address receiver,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.BORROW;
        data = abi.encode(asset, amount, receiver, maxIterations, op);
    }

    function _getRepayData(address asset, uint256 amount, address onBehalf, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.REPAY;
        data = abi.encode(asset, amount, onBehalf, op);
    }

    function _getWithdrawData(
        address asset,
        uint256 amount,
        address receiver,
        uint256 maxIterations,
        IBulkerGateway.OpType op
    ) internal pure returns (IBulkerGateway.ActionType action, bytes memory data) {
        action = IBulkerGateway.ActionType.WITHDRAW;
        data = abi.encode(asset, amount, receiver, maxIterations, op);
    }

    function _getWithdrawCollateralData(address asset, uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WITHDRAW_COLLATERAL;
        data = abi.encode(asset, amount, receiver, op);
    }

    function _getClaimRewardsData(address[] memory assets, address onBehalf)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.CLAIM_REWARDS;
        data = abi.encode(assets, onBehalf);
    }

    function _getWrapETHData(uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WRAP_ETH;
        data = abi.encode(amount, op);
    }

    function _getUnwrapETHData(uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.UNWRAP_ETH;
        data = abi.encode(amount, receiver, op);
    }

    function _getWrapStETHData(uint256 amount, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.WRAP_ST_ETH;
        data = abi.encode(amount, op);
    }

    function _getUnwrapStETHData(uint256 amount, address receiver, IBulkerGateway.OpType op)
        internal
        pure
        returns (IBulkerGateway.ActionType action, bytes memory data)
    {
        action = IBulkerGateway.ActionType.UNWRAP_ST_ETH;
        data = abi.encode(amount, receiver, op);
    }
}
