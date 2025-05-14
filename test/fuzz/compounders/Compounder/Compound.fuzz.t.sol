/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../src/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "compound" of contract "Compounder".
 */
contract Compound_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compound_Reentered(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidAccount(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidInitiator(
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Revert_compound_ChangeAccountOwnership(
        Compounder.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Compounder is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounder), true);

        // And: Compounder is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(compounder), true);

        // And: The initiator is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0.001 * 1e18, MAX_FEE);
        vm.prank(initiator);
        compounder.setInitiatorInfo(0, fee, tolerance, MIN_LIQUIDITY_RATIO);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator);

        // And: Account is transferred to newOwner.
        vm.startPrank(account.owner());
        factory.safeTransferFrom(account.owner(), newOwner, address(account));
        vm.stopPrank();

        // When : calling compound
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }
}
