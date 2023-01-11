// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Morpho} from "../src/Morpho.sol";
import {Errors} from "../src/libraries/Errors.sol";
import "./helpers/SigUtils.sol";
import "./helpers/MorphoTest.sol";

contract TestApproval is Morpho, MorphoTest {
    SigUtils internal sigUtils;
    uint256 internal ownerPrivateKey;
    uint256 internal managerPrivateKey;
    address internal ownerAdd;
    address internal managerAdd;

    function setUp() public override {
        super.setUp();

        sigUtils = new SigUtils(this.DOMAIN_SEPARATOR());

        ownerPrivateKey = 0xA11CE;
        managerPrivateKey = 0xB0B;

        ownerAdd = vm.addr(ownerPrivateKey);
        managerAdd = vm.addr(managerPrivateKey);
    }

    function testApproveManager(address owner, address manager, bool isAllowed) public {
        vm.prank(owner);
        this.approveManager(manager, isAllowed);
        assertEq(this.isManaging(owner, manager), isAllowed);
    }

    function testApproveManagerWithSig(uint128 deadline) public {
        vm.assume(deadline > block.timestamp);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: ownerAdd,
            manager: managerAdd,
            isAllowed: true,
            nonce: this.userNonce(ownerAdd),
            deadline: block.timestamp + deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );

        assertEq(this.isManaging(ownerAdd, managerAdd), true);
        assertEq(this.userNonce(ownerAdd), 1);
    }

    function testRevertExpiredApproveManagerWithSig(uint128 deadline) public {
        vm.assume(deadline <= block.timestamp);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: ownerAdd,
            manager: managerAdd,
            isAllowed: true,
            nonce: this.userNonce(ownerAdd),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(Errors.SignatureExpired.selector));
        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );
    }

    function testRevertInvalidSignatoryApproveManagerWithSig() public {
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: ownerAdd,
            manager: managerAdd,
            isAllowed: true,
            nonce: this.userNonce(ownerAdd),
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(managerPrivateKey, digest); // manager signs owner's approval.

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSignatory.selector));
        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );
    }

    function testRevertInvalidNonceApproveManagerWithSig(uint256 nonce) public {
        vm.assume(nonce != this.userNonce(ownerAdd));

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: ownerAdd,
            manager: managerAdd,
            isAllowed: true,
            nonce: nonce,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector));
        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );
    }

    function testRevertSignatureReplayApproveManagerWithSig() public {
        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: ownerAdd,
            manager: managerAdd,
            isAllowed: true,
            nonce: this.userNonce(ownerAdd),
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector));
        this.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );
    }
}
