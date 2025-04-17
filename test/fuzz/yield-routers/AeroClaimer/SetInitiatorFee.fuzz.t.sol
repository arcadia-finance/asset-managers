/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/yield-routers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";

/**
 * @notice Fuzz tests for the function "setInitatorFee" of contract "AeroClaimer".
 */
contract SetInitiatorFee_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        AeroClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setInitiatorFee_Reentered(address random, uint256 initiatorFee) public {
        // Given: Account is not address(0).
        vm.assume(random != address(0));

        // And: An account address is defined in storage.
        aeroClaimer.setAccount(random);

        // When: Calling setInitiatorFee().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.Reentered.selector);
        aeroClaimer.setInitiatorFee(initiatorFee);
    }

    function testFuzz_Revert_setInitiatorFee_InvalidValue_MaxInitiatorFee(uint256 initiatorFee) public {
        // Given: initiatorFee is higher than maxInitiatorFee.
        initiatorFee = bound(initiatorFee, MAX_INITIATOR_SHARE + 1, type(uint256).max);

        // When: Calling setInitatorFee().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.InvalidValue.selector);
        aeroClaimer.setInitiatorFee(initiatorFee);
    }

    function testFuzz_Revert_setInitiatorFee_InvalidValue_DecreaseOnly(uint256 initialFee, uint256 newFee) public {
        // Given: initiatorFee is higher than maxInitiatorFee.
        initialFee = bound(initialFee, 0, MAX_INITIATOR_SHARE - 1);
        newFee = bound(newFee, initialFee + 1, MAX_INITIATOR_SHARE);

        // And: Initiator fee has already been set.
        aeroClaimer.setInitiatorFee(initialFee);

        // When: Updating the initiator fee with a fee amount > initial amount.
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.InvalidValue.selector);
        aeroClaimer.setInitiatorFee(newFee);
    }

    function testFuzz_Success_setInitiatorFee_First(uint256 initiatorFee, address initiator_) public {
        // Given: initiatorFee is below or equal to maxInitiatorFee.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_SHARE);

        // And: Initiator is not equal to initiator that is already set.
        vm.assume(initiator_ != initiator);

        // And: Initiator is not yet set.
        assertEq(aeroClaimer.initiatorSet(initiator_), false);

        // When: Calling setInitiatorFee().
        vm.prank(initiator_);
        aeroClaimer.setInitiatorFee(initiatorFee);

        // Then: Initiator should be labelled as set.
        assertEq(aeroClaimer.initiatorSet(initiator_), true);
        // And: Fee should be correct.
        assertEq(aeroClaimer.initiatorFee(initiator_), initiatorFee);
    }

    function testFuzz_Success_setInitiatorFee_UpdateFee(uint256 initialFee, uint256 newFee, address initiator_)
        public
    {
        // Given: initialFee is below or equal to maxInitiatorFee.
        initialFee = bound(initialFee, 1, MAX_INITIATOR_SHARE - 1);
        // And: updated fee is lower thab initialFee.
        newFee = bound(newFee, 0, initialFee);

        // And: Initiator is not equal to initiator that is already set.
        vm.assume(initiator_ != initiator);

        // And: Initiator is not yet set.
        assertEq(aeroClaimer.initiatorSet(initiator_), false);

        // And: InitiatorFee has been set a first time.
        vm.prank(initiator_);
        aeroClaimer.setInitiatorFee(initialFee);

        // When: updating the fee with a lower value.
        vm.prank(initiator_);
        aeroClaimer.setInitiatorFee(newFee);

        // Then: Initiator should be labelled as set.
        assertEq(aeroClaimer.initiatorSet(initiator_), true);
        // And: Fee should be correct.
        assertEq(aeroClaimer.initiatorFee(initiator_), newFee);
    }
}
