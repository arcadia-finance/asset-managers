/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "SlipstreamCompounder".
 */
contract Constructor_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_Constructor_UnderflowTolerance(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        SlipstreamCompounder compounder_ = new SlipstreamCompounder(maxTolerance, maxInitiatorShare);

        assertEq(compounder_.MAX_TOLERANCE(), maxTolerance);
        assertEq(compounder_.MAX_FEE(), maxInitiatorShare);
    }
}
