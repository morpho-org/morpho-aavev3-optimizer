// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IAllowanceTransfer} from "@permit2/AllowanceTransfer.sol";
import {SafeCast160} from "@permit2/libraries/SafeCast160.sol";
import {console2} from "@forge-std/console2.sol";
import {console} from "@forge-std/console.sol";
import {SigUtils} from "test/helpers/SigUtils.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationPermit2 is IntegrationTest {
    SigUtils internal sigUtils;

    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

    bytes32 public constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    function setUp() public override {
        super.setUp();

        sigUtils = new SigUtils(morpho.DOMAIN_SEPARATOR());
    }

    function defaultERC20PermitAllowance(
        address token0,
        uint160 amount,
        uint48 expiration,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (IAllowanceTransfer.PermitSingle memory) {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: token0,
            amount: amount,
            expiration: expiration,
            nonce: uint48(nonce)
        });
        return IAllowanceTransfer.PermitSingle({details: details, spender: address(morpho), sigDeadline: deadline});
    }

    function getPermitSignatureRaw(
        IAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s, bytes32 msgHash) {
        bytes32 permitHash = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details));

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, permit.spender, permit.sigDeadline))
            )
        );

        (v, r, s) = vm.sign(privateKey, msgHash);
    }

    function testSupplyWithPermit2(uint256 privateKey, uint256 deadline, uint256 amount) public {
        vm.assume(block.timestamp < deadline);
        privateKey = _boundAmountNotZero(privateKey);
        address delegator = vm.addr(privateKey);
        vm.assume(delegator != address(0));

        console.log(delegator, privateKey);
        TestMarket storage market = testMarkets[underlyings[0]];

        amount = _boundSupply(market, amount);
        uint160 supplied = uint160(Math.min(type(uint160).max, amount));

        uint256 nounce = morpho.userNonce(delegator);

        IAllowanceTransfer.PermitSingle memory permit =
            defaultERC20PermitAllowance(market.underlying, supplied, type(uint48).max, nounce, deadline);
        bytes32 msgHash;
        Types.Signature memory sig;
        (sig.v, sig.r, sig.s, msgHash) = getPermitSignatureRaw(permit, privateKey, morpho.DOMAIN_SEPARATOR());
        address signer = ecrecover(msgHash, sig.v, sig.r, sig.s);
        console.log(delegator, signer);
        assertEq(signer, delegator);
        console.log(permit.sigDeadline, deadline);
        console.log(permit.spender);
        deal(market.underlying, delegator, supplied);
        vm.prank(delegator);
        morpho.supplyWithPermit(market.underlying, supplied, delegator, 10, deadline, sig);
    }
}
