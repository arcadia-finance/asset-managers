/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ECDSA } from "../../../../lib/accounts-v2/lib/solady/src/utils/ECDSA.sol";

/**
 * @notice Fuzz tests for the function "isValidSignature" of contract "CowSwapper".
 */
contract IsValidSignature_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_isValidSignature_InvalidOrderHash(
        address account_,
        address caller,
        bytes32 orderHash,
        bytes32 messageHash,
        bytes32 orderHash_,
        bytes calldata signature
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: The orderHash is not correct.
        vm.assume(orderHash != orderHash_);

        // And: Transient state is set.
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        // When: Caller calls isValidSignature.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.InvalidOrderHash.selector);
        cowSwapper.isValidSignature(orderHash_, signature);
    }

    function testFuzz_Revert_isValidSignature_InvalidSignatureLength(
        address account_,
        address caller,
        bytes32 orderHash,
        bytes32 messageHash,
        bytes calldata invalidSignature
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: Invalid signature length.
        vm.assume(invalidSignature.length != 65 && invalidSignature.length != 64);

        // And: Transient state is set.
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        // When: Caller calls isValidSignature.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(ECDSA.InvalidSignature.selector);
        cowSwapper.isValidSignature(orderHash, invalidSignature);
    }

    function testFuzz_Revert_isValidSignature_InvalidSignatureLength(
        address account_,
        address caller,
        bytes32 orderHash,
        bytes32 messageHash,
        bytes32 r,
        bytes32 s,
        bytes1 invalidV
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: Invalid signature.
        vm.assume(invalidV != bytes1(uint8(27)) && invalidV != bytes1(uint8(28)));
        bytes memory invalidSignature = new bytes(65);
        assembly {
            mstore(add(invalidSignature, 32), r)
            mstore(add(invalidSignature, 64), s)
            mstore8(add(invalidSignature, 96), invalidV)
        }

        // And: Transient state is set.
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        // When: Caller calls isValidSignature.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(ECDSA.InvalidSignature.selector);
        cowSwapper.isValidSignature(orderHash, invalidSignature);
    }

    function testFuzz_Revert_isValidSignature_InvalidSigner(
        address account_,
        address caller,
        address accountOwner,
        address initiator,
        bytes32 orderHash,
        bytes32 messageHash,
        uint256 signerPrivateKey
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: Valid signer.
        signerPrivateKey = givenValidPrivatekey(signerPrivateKey);

        // And: Signer is not the initiator or the account owner.
        vm.assume(accountOwner != vm.addr(signerPrivateKey));
        vm.assume(initiator != vm.addr(signerPrivateKey));

        // And: Transient state is set.
        cowSwapper.setAccountOwner(accountOwner);
        cowSwapper.setInitiator(initiator);
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        bytes memory signature = getSignature(messageHash, signerPrivateKey);

        // When: Caller calls isValidSignature.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.InvalidSigner.selector);
        cowSwapper.isValidSignature(orderHash, signature);
    }

    function testFuzz_Success_isValidSignature_NoAccountSet(address caller, bytes32 orderHash, bytes memory signature)
        public
    {
        // Given: No Account is set.
        cowSwapper.setAccount(address(0));

        // When: Caller calls isValidSignature.
        vm.prank(caller);
        bytes4 magicValue = cowSwapper.isValidSignature(orderHash, signature);

        // Then: Magic value is returned.
        assertEq(magicValue, bytes4(0x1626ba7e));
    }

    function testFuzz_Success_isValidSignature_AccountOwner(
        address account_,
        address caller,
        address initiator,
        bytes32 orderHash,
        bytes32 messageHash,
        uint256 accountOwnerPrivateKey
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: Valid accountOwner.
        accountOwnerPrivateKey = givenValidPrivatekey(accountOwnerPrivateKey);
        address accountOwner = vm.addr(accountOwnerPrivateKey);

        // And: Transient state is set.
        cowSwapper.setAccountOwner(accountOwner);
        cowSwapper.setInitiator(initiator);
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        bytes memory signature = getSignature(messageHash, accountOwnerPrivateKey);

        // When: Caller calls isValidSignature.
        vm.prank(caller);
        bytes4 magicValue = cowSwapper.isValidSignature(orderHash, signature);

        // Then: Magic value is returned.
        assertEq(magicValue, bytes4(0x1626ba7e));
    }

    function testFuzz_Success_isValidSignature_Initiator(
        address account_,
        address caller,
        address accountOwner,
        bytes32 orderHash,
        bytes32 messageHash,
        uint256 initiatorPrivateKey
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // And: Valid initiator.
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Transient state is set.
        cowSwapper.setAccountOwner(accountOwner);
        cowSwapper.setInitiator(initiator);
        cowSwapper.setOrderHash(orderHash);
        cowSwapper.setMessageHash(messageHash);

        bytes memory signature = getSignature(messageHash, initiatorPrivateKey);

        // When: Caller calls isValidSignature.
        vm.prank(caller);
        bytes4 magicValue = cowSwapper.isValidSignature(orderHash, signature);

        // Then: Magic value is returned.
        assertEq(magicValue, bytes4(0x1626ba7e));
    }
}
