// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Errors} from "../src/libraries/Errors.sol";

import {Morpho} from "../src/Morpho.sol";

import {SigUtils} from "./helpers/SigUtils.sol";
import "./helpers/IntegrationTest.sol";

contract TestApproval is IntegrationTest {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant MANAGER_PK = 0xB0B;

    address internal immutable OWNER = vm.addr(OWNER_PK);
    address internal immutable MANAGER = vm.addr(MANAGER_PK);

    SigUtils internal sigUtils;

    function setUp() public override {
        super.setUp();

        sigUtils = new SigUtils(morpho.DOMAIN_SEPARATOR());
    }

    function testApproveManager(address owner, address manager, bool isAllowed) public {
        vm.prank(owner);
        morpho.approveManager(manager, isAllowed);
        assertEq(morpho.isManaging(owner, manager), isAllowed);
    }

    function testApproveManagerWithSig(uint128 deadline) public {
        vm.assume(deadline > block.timestamp);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: OWNER,
            manager: MANAGER,
            isAllowed: true,
            nonce: morpho.userNonce(OWNER),
            deadline: block.timestamp + deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        morpho.approveManagerWithSig(
            authorization.owner,
            authorization.manager,
            authorization.isAllowed,
            authorization.nonce,
            authorization.deadline,
            v,
            r,
            s
        );

        assertEq(morpho.isManaging(OWNER, MANAGER), true);
        assertEq(morpho.userNonce(OWNER), 1);
    }

    function testRevertExpiredApproveManagerWithSig(uint128 deadline) public {
        vm.assume(deadline <= block.timestamp);

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: OWNER,
            manager: MANAGER,
            isAllowed: true,
            nonce: morpho.userNonce(OWNER),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vm.expectRevert(abi.encodeWithSelector(Errors.SignatureExpired.selector));
        morpho.approveManagerWithSig(
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
            owner: OWNER,
            manager: MANAGER,
            isAllowed: true,
            nonce: morpho.userNonce(OWNER),
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MANAGER_PK, digest); // manager signs owner's approval.

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSignatory.selector));
        morpho.approveManagerWithSig(
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
        vm.assume(nonce != morpho.userNonce(OWNER));

        SigUtils.Authorization memory authorization = SigUtils.Authorization({
            owner: OWNER,
            manager: MANAGER,
            isAllowed: true,
            nonce: nonce,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector));
        morpho.approveManagerWithSig(
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
            owner: OWNER,
            manager: MANAGER,
            isAllowed: true,
            nonce: morpho.userNonce(OWNER),
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(authorization);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        morpho.approveManagerWithSig(
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
        morpho.approveManagerWithSig(
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
