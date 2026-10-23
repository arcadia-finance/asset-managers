/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";
import { CloserExtension } from "../../../../utils/extensions/CloserExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Closer".
 */
contract Constructor_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        CloserExtension closer_ = new CloserExtension(owner_, arcadiaFactory);

        assertEq(closer_.owner(), owner_);
        assertEq(closer_.getAccount(), address(0));
    }
}
