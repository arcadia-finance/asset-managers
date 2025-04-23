/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamFixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { SlipstreamLogicExtension } from "../../../../utils/extensions/SlipstreamLogicExtension.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";

/**
 * @notice Common logic needed by all "SlipstreamLogic" fuzz tests.
 */
abstract contract SlipstreamLogic_Fuzz_Test is Fuzz_Test, SlipstreamFixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SlipstreamLogicExtension internal slipstreamLogic;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, SlipstreamFixture) {
        Fuzz_Test.setUp();

        slipstreamLogic = new SlipstreamLogicExtension();

        // And: Slipstream fixtures are deployed.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
}
