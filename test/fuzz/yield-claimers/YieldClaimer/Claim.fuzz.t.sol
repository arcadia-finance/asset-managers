/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract ClaimAero_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(YieldClaimer_Fuzz_Test) {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_claim_Reentered(address positionmanager, address random, uint256 tokenId) public {
        // Given: Account is not address(0).
        vm.assume(random != address(0));

        // And: An account address is defined in storage.
        yieldClaimer.setAccount(random);

        // When: Calling claim().
        // Then: It should revert.
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.claim(address(account), positionmanager, tokenId);
    }

    function testFuzz_Revert_claim_InvalidInitiator(address positionmanager, address notInitiator, uint256 tokenId)
        public
    {
        // Given: The caller is not the initiator.
        vm.assume(initiatorYieldClaimer != notInitiator);
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // When: Calling claim().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), positionmanager, tokenId);
    }

    // All others cases are covered in Claim*.fuzz.t.sol
}
