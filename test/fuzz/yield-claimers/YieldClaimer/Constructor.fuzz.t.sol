/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";
import { YieldClaimerExtension } from "../../../utils/extensions/YieldClaimerExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimer".
 */
contract Constructor_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address arcadiaFactory, uint256 maxFee) public {
        vm.prank(users.owner);
        YieldClaimerExtension yieldClaimer_ = new YieldClaimerExtension(arcadiaFactory, maxFee);

        assertEq(address(yieldClaimer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(yieldClaimer_.MAX_FEE(), maxFee);
    }
}
