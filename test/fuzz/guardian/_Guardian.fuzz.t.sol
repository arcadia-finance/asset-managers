/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../Fuzz.t.sol";
import { GuardianExtension } from "../../utils/extensions/GuardianExtension.sol";

/**
 * @notice Common logic needed by all "Guardian" fuzz tests.
 */
abstract contract Guardian_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    GuardianExtension internal guardian;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        guardian = new GuardianExtension(users.owner);
    }
}
