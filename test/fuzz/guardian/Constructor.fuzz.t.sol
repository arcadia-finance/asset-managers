/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Guardian_Fuzz_Test } from "./_Guardian.fuzz.t.sol";
import { GuardianExtension } from "../../utils/extensions/GuardianExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Guardian".
 */
contract Constructor_Guardian_Fuzz_Test is Guardian_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    // forge-lint: disable-next-item(empty-block)
    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address guardian_) public {
        GuardianExtension guardianExtension = new GuardianExtension(owner_, guardian_);

        assertEq(guardianExtension.owner(), owner_);
        assertEq(guardianExtension.guardian(), guardian_);
    }
}
