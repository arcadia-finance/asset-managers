/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Errors } from "../../../../lib/accounts-v2/lib/merkl-contracts/contracts/utils/Errors.sol";
import { MerkleTree } from "../../../../lib/accounts-v2/lib/merkl-contracts/contracts/Distributor.sol";
import { Guardian } from "../../../../src/guardian/Guardian.sol";
import { MerklOperatorBase } from "../../../../src/merkl-operator/MerklOperatorBase.sol";
import { MerklOperatorBase_Fuzz_Test } from "./_MerklOperatorBase.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "MerklOperatorBase".
 */
contract Claim_MerklOperatorBase_Fuzz_Test is MerklOperatorBase_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperatorBase_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_claim_Paused(
        address account_,
        MerklOperatorBase.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Yield Claimer is Paused.
        vm.prank(users.owner);
        merklOperator.setPauseFlag(true);

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        merklOperator.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidAccount(
        address account_,
        MerklOperatorBase.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        merklOperator.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidInitiator(
        MerklOperatorBase.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperatorBase.InvalidInitiator.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_ChangeAccountOwnership(
        MerklOperatorBase.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: MerklOperatorBase is allowed as Asset Manager.
        address[] memory merklOperators = new address[](1);
        merklOperators[0] = address(merklOperator);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));

        // And: MerklOperatorBase is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(MerklOperatorBase.InvalidInitiator.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidLengths_Amounts(
        address initiator,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holding balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: merklOperator is set.
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account has Merkl rewards.
        tokenState0.amount = uint128(bound(tokenState0.amount, tokenState0.claimed, type(uint128).max));
        tokenState1.amount = uint128(bound(tokenState1.amount, tokenState1.claimed, type(uint128).max));
        distributor.setClaimed(address(account), address(token0), tokenState0.claimed);
        distributor.setClaimed(address(account), address(token1), tokenState1.claimed);
        deal(address(token0), address(distributor), tokenState0.amount - tokenState0.claimed, true);
        deal(address(token1), address(distributor), tokenState1.amount - tokenState1.claimed, true);
        bytes32 leaf0 = keccak256(abi.encode(address(account), address(token0), tokenState0.amount));
        bytes32 leaf1 = keccak256(abi.encode(address(account), address(token1), tokenState1.amount));
        bytes32 root = commutativeKeccak256(leaf0, leaf1);
        vm.prank(users.owner);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: "" }));

        // When: Calling claim().
        // Then: Transaction should revert with InvalidLengths.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokenState0.amount;
        bytes32[][] memory proofs = new bytes32[][](2);
        bytes32[] memory proofs0 = new bytes32[](1);
        proofs0[0] = leaf1;
        proofs[0] = proofs0;
        bytes32[] memory proofs1 = new bytes32[](1);
        proofs1[0] = leaf0;
        proofs[1] = proofs1;
        vm.prank(initiator);
        vm.expectRevert(Errors.InvalidLengths.selector);
        merklOperator.claim(
            address(account), MerklOperatorBase.InitiatorParams({ tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Revert_claim_InvalidLengths_Proofs(
        address initiator,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holding balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: merklOperator is set.
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account has Merkl rewards.
        tokenState0.amount = uint128(bound(tokenState0.amount, tokenState0.claimed, type(uint128).max));
        tokenState1.amount = uint128(bound(tokenState1.amount, tokenState1.claimed, type(uint128).max));
        distributor.setClaimed(address(account), address(token0), tokenState0.claimed);
        distributor.setClaimed(address(account), address(token1), tokenState1.claimed);
        deal(address(token0), address(distributor), tokenState0.amount - tokenState0.claimed, true);
        deal(address(token1), address(distributor), tokenState1.amount - tokenState1.claimed, true);
        bytes32 leaf0 = keccak256(abi.encode(address(account), address(token0), tokenState0.amount));
        bytes32 leaf1 = keccak256(abi.encode(address(account), address(token1), tokenState1.amount));
        bytes32 root = commutativeKeccak256(leaf0, leaf1);
        vm.prank(users.owner);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: "" }));

        // When: Calling claim().
        // Then: Transaction should revert with InvalidLengths.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenState0.amount;
        amounts[1] = tokenState1.amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        bytes32[] memory proofs0 = new bytes32[](1);
        proofs0[0] = leaf1;
        proofs[0] = proofs0;
        vm.prank(initiator);
        vm.expectRevert(Errors.InvalidLengths.selector);
        merklOperator.claim(
            address(account), MerklOperatorBase.InitiatorParams({ tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Revert_claim_InvalidProof(
        address initiator,
        TokenState memory tokenState0,
        TokenState memory tokenState1,
        bytes32 invalidProof
    ) public {
        // Given: initiator is not holding balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: merklOperator is set.
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account has Merkl rewards.
        tokenState0.amount = uint128(bound(tokenState0.amount, tokenState0.claimed, type(uint128).max));
        tokenState1.amount = uint128(bound(tokenState1.amount, tokenState1.claimed, type(uint128).max));
        distributor.setClaimed(address(account), address(token0), tokenState0.claimed);
        distributor.setClaimed(address(account), address(token1), tokenState1.claimed);
        deal(address(token0), address(distributor), tokenState0.amount - tokenState0.claimed, true);
        deal(address(token1), address(distributor), tokenState1.amount - tokenState1.claimed, true);
        bytes32 leaf0 = keccak256(abi.encode(address(account), address(token0), tokenState0.amount));
        bytes32 leaf1 = keccak256(abi.encode(address(account), address(token1), tokenState1.amount));
        bytes32 root = commutativeKeccak256(leaf0, leaf1);
        vm.prank(users.owner);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: "" }));

        // When: Calling claim().
        // Then: Transaction should revert with InvalidProof.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenState0.amount;
        amounts[1] = tokenState1.amount;
        bytes32[][] memory proofs = new bytes32[][](2);
        bytes32[] memory proofs0 = new bytes32[](1);
        proofs0[0] = invalidProof;
        proofs[0] = proofs0;
        vm.prank(initiator);
        vm.expectRevert(Errors.InvalidProof.selector);
        merklOperator.claim(
            address(account), MerklOperatorBase.InitiatorParams({ tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Success_claim_NoDuplicateTokens(
        address initiator,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holding balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: merklOperator is set.
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account has Merkl rewards.
        tokenState0.amount = uint128(bound(tokenState0.amount, tokenState0.claimed, type(uint128).max));
        tokenState1.amount = uint128(bound(tokenState1.amount, tokenState1.claimed, type(uint128).max));
        distributor.setClaimed(address(account), address(token0), tokenState0.claimed);
        distributor.setClaimed(address(account), address(token1), tokenState1.claimed);
        deal(address(token0), address(distributor), tokenState0.amount - tokenState0.claimed, true);
        deal(address(token1), address(distributor), tokenState1.amount - tokenState1.claimed, true);
        bytes32 leaf0 = keccak256(abi.encode(address(account), address(token0), tokenState0.amount));
        bytes32 leaf1 = keccak256(abi.encode(address(account), address(token1), tokenState1.amount));
        bytes32 root = commutativeKeccak256(leaf0, leaf1);
        vm.prank(users.owner);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: "" }));

        // When: Calling claim().
        {
            address[] memory tokens = new address[](2);
            tokens[0] = address(token0);
            tokens[1] = address(token1);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = tokenState0.amount;
            amounts[1] = tokenState1.amount;
            bytes32[][] memory proofs = new bytes32[][](2);
            bytes32[] memory proofs0 = new bytes32[](1);
            proofs0[0] = leaf1;
            proofs[0] = proofs0;
            bytes32[] memory proofs1 = new bytes32[](1);
            proofs1[0] = leaf0;
            proofs[1] = proofs1;
            vm.prank(initiator);
            merklOperator.claim(
                address(account),
                MerklOperatorBase.InitiatorParams({ tokens: tokens, amounts: amounts, proofs: proofs })
            );
        }

        // Then: Claimed and balances are updated.
        (uint208 amount,,) = distributor.claimed(address(account), address(token0));
        assertEq(amount, tokenState0.amount);
        uint256 reward = tokenState0.amount - tokenState0.claimed;
        assertEq(token0.balanceOf(address(account)), reward);

        (amount,,) = distributor.claimed(address(account), address(token1));
        assertEq(amount, tokenState1.amount);
        reward = tokenState1.amount - tokenState1.claimed;
        assertEq(token1.balanceOf(address(account)), reward);
    }

    function testFuzz_Success_claim_DuplicateTokens(address initiator, TokenState memory tokenState0, bytes32 leaf1)
        public
    {
        // Given: initiator is not holding balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: merklOperator is set.
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(account), new address[](0));
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // And: Account has Merkl rewards.
        tokenState0.amount = uint128(bound(tokenState0.amount, tokenState0.claimed, type(uint128).max));
        distributor.setClaimed(address(account), address(token0), tokenState0.claimed);
        deal(address(token0), address(distributor), tokenState0.amount - tokenState0.claimed, true);
        bytes32 leaf0 = keccak256(abi.encode(address(account), address(token0), tokenState0.amount));
        bytes32 root = commutativeKeccak256(leaf0, leaf1);
        vm.prank(users.owner);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: "" }));

        // When: Calling claim().
        {
            address[] memory tokens = new address[](2);
            tokens[0] = address(token0);
            tokens[1] = address(token0);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = tokenState0.amount;
            amounts[1] = tokenState0.amount;
            bytes32[][] memory proofs = new bytes32[][](2);
            bytes32[] memory proofs0 = new bytes32[](1);
            proofs0[0] = leaf1;
            proofs[0] = proofs0;
            bytes32[] memory proofs1 = new bytes32[](1);
            proofs1[0] = leaf1;
            proofs[1] = proofs1;
            vm.prank(initiator);
            merklOperator.claim(
                address(account),
                MerklOperatorBase.InitiatorParams({ tokens: tokens, amounts: amounts, proofs: proofs })
            );
        }

        // Then: Claimed and balances are updated.
        (uint208 amount,,) = distributor.claimed(address(account), address(token0));
        assertEq(amount, tokenState0.amount);
        uint256 reward = tokenState0.amount - tokenState0.claimed;
        assertEq(token0.balanceOf(address(account)), reward);
    }
}
