/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer2.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorInfo" of contract "YieldClaimer".
 */
contract SetInitiatorInfo_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiatorInfo_Reentered(address initiator, address account_, uint256 claimFee) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.setInitiatorInfo(claimFee);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidMaxFee(address initiator, uint256 claimFee)
        public
    {
        // Given: claimFee is > Max Initiator Fee
        claimFee = bound(claimFee, yieldClaimer.MAX_FEE() + 1, type(uint256).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(YieldClaimer.InvalidValue.selector);
        yieldClaimer.setInitiatorInfo(claimFee);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidMaxFee(
        address initiator,
        uint256 initClaimFee,
        uint256 newClaimFee
    ) public {
        // Given: Initiator is initialised.
        initClaimFee = bound(initClaimFee, 0, yieldClaimer.MAX_FEE());
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(initClaimFee);

        // And: New Fee is > initial swapFee.
        newClaimFee = bound(newClaimFee, initClaimFee + 1, type(uint256).max);

        // When: Initiator updates the swapFee to a higher value.
        // Then: It should revert.
        vm.expectRevert(YieldClaimer.InvalidValue.selector);
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(newClaimFee);
    }

    function testFuzz_Success_setInitiatorInfo_NotInitialised(address initiator, uint256 claimFee) public {
        // Given: claimFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, yieldClaimer.MAX_FEE());

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(claimFee);

        // Then: Values should be set and correct.
        (bool set, uint256 claimFee_) = yieldClaimer.initiatorInfo(initiator);
        assertTrue(set);
        assertEq(claimFee, claimFee_);
    }

    function testFuzz_Success_setInitiatorInfo_Initialised(address initiator, uint256 initClaimFee, uint256 newClaimFee)
        public
    {
        // Given: Initiator is initialised.
        initClaimFee = bound(initClaimFee, 0, yieldClaimer.MAX_FEE());
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(initClaimFee);

        // And: New Fee is < initial swapFee.
        newClaimFee = bound(newClaimFee, 0, initClaimFee);

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(newClaimFee);

        // Then: Values should be set and correct.
        (bool set, uint256 claimFee_) = yieldClaimer.initiatorInfo(initiator);
        assertTrue(set);
        assertEq(newClaimFee, claimFee_);
    }
}
