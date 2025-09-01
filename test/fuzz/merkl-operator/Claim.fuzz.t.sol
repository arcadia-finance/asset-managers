/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Errors } from "../../../lib/accounts-v2/lib/merkl-contracts/contracts/utils/Errors.sol";
import { Distributor, MerkleTree } from "../../../lib/accounts-v2/lib/merkl-contracts/contracts/Distributor.sol";
import { Guardian } from "../../../src/guardian/Guardian.sol";
import { MerklOperator } from "../../../src/merkl-operator/MerklOperator.sol";
import { MerklOperator_Fuzz_Test } from "./_MerklOperator.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "MerklOperator".
 */
contract Claim_MerklOperator_Fuzz_Test is MerklOperator_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperator_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_claim_Paused(
        address account_,
        MerklOperator.InitiatorParams memory initiatorParams,
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
        MerklOperator.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

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
        MerklOperator.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperator.InvalidInitiator.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_ChangeAccountOwnership(
        MerklOperator.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: MerklOperator is allowed as Asset Manager.
        address[] memory merklOperators = new address[](1);
        merklOperators[0] = address(merklOperator);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), new address[](0));

        // And: MerklOperator is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), new address[](0));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(MerklOperator.InvalidInitiator.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidValue(MerklOperator.InitiatorParams memory initiatorParams, address initiator)
        public
    {
        // Given : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: MerklOperator is allowed as Asset Manager.
        address[] memory merklOperators = new address[](1);
        merklOperators[0] = address(merklOperator);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), new address[](0));

        // And: Account is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is invalid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, MAX_FEE + 1, type(uint64).max));

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(MerklOperator.InvalidValue.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidClaimRecipient(
        MerklOperator.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: MerklOperator is allowed as Asset Manager.
        address[] memory merklOperators = new address[](1);
        merklOperators[0] = address(merklOperator);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), new address[](0));

        // And: Account is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: MerklOperator is not set as claim recipient for tokens.
        vm.assume(initiatorParams.tokens.length > 0);

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(MerklOperator.InvalidClaimRecipient.selector);
        merklOperator.claim(address(account), initiatorParams);
    }

    function testFuzz_Success_claim_InvalidLengths_Amounts(
        address initiator,
        address recipient,
        uint256 claimFee,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not holdig balances.
        vm.assume(recipient != address(merklOperator));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(0));

        // And: merklOperator is set.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), tokens);
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        claimFee = bound(claimFee, 0, MAX_FEE);

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
            address(account),
            MerklOperator.InitiatorParams({ claimFee: claimFee, tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Success_claim_InvalidLengths_Proofs(
        address initiator,
        address recipient,
        uint256 claimFee,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not holdig balances.
        vm.assume(recipient != address(merklOperator));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(0));

        // And: merklOperator is set.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), tokens);
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        claimFee = bound(claimFee, 0, MAX_FEE);

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
            address(account),
            MerklOperator.InitiatorParams({ claimFee: claimFee, tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Success_claim_InvalidProof(
        address initiator,
        address recipient,
        uint256 claimFee,
        TokenState memory tokenState0,
        TokenState memory tokenState1,
        bytes32 invalidProof
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not holdig balances.
        vm.assume(recipient != address(merklOperator));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(0));

        // And: merklOperator is set.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), tokens);
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        claimFee = bound(claimFee, 0, MAX_FEE);

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
            address(account),
            MerklOperator.InitiatorParams({ claimFee: claimFee, tokens: tokens, amounts: amounts, proofs: proofs })
        );
    }

    function testFuzz_Success_claim_NoDuplicateTokens(
        address initiator,
        address recipient,
        uint256 claimFee,
        TokenState memory tokenState0,
        TokenState memory tokenState1
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not holdig balances.
        vm.assume(recipient != address(merklOperator));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(0));

        // And: merklOperator is set.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), tokens);
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        claimFee = bound(claimFee, 0, MAX_FEE);

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
                MerklOperator.InitiatorParams({ claimFee: claimFee, tokens: tokens, amounts: amounts, proofs: proofs })
            );
        }

        // Then: Claimed and balances are updated.
        (uint208 amount,,) = distributor.claimed(address(account), address(token0));
        assertEq(amount, tokenState0.amount);
        uint256 reward = tokenState0.amount - tokenState0.claimed;
        uint256 fee = reward * claimFee / 1e18;
        assertEq(token0.balanceOf(initiator), fee);
        assertEq(token0.balanceOf(recipient), reward - fee);

        (amount,,) = distributor.claimed(address(account), address(token1));
        assertEq(amount, tokenState1.amount);
        reward = tokenState1.amount - tokenState1.claimed;
        fee = reward * claimFee / 1e18;
        assertEq(token1.balanceOf(initiator), fee);
        assertEq(token1.balanceOf(recipient), reward - fee);
    }

    function testFuzz_Success_claim_DuplicateTokens(
        address initiator,
        address recipient,
        uint256 claimFee,
        TokenState memory tokenState0,
        bytes32 leaf1
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(merklOperator));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not holdig balances.
        vm.assume(recipient != address(merklOperator));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(0));

        // And: merklOperator is set.
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token0);
        {
            address[] memory merklOperators = new address[](1);
            merklOperators[0] = address(merklOperator);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setMerklOperators(merklOperators, statuses, new bytes[](1), address(merklOperator), tokens);
        }

        // And: Account info is set.
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        claimFee = bound(claimFee, 0, MAX_FEE);

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
                MerklOperator.InitiatorParams({ claimFee: claimFee, tokens: tokens, amounts: amounts, proofs: proofs })
            );
        }

        // Then: Claimed and balances are updated.
        (uint208 amount,,) = distributor.claimed(address(account), address(token0));
        assertEq(amount, tokenState0.amount);
        uint256 reward = tokenState0.amount - tokenState0.claimed;
        uint256 fee = reward * claimFee / 1e18;
        assertEq(token0.balanceOf(initiator), fee);
        assertEq(token0.balanceOf(recipient), reward - fee);
    }
}
