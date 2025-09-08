/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { YieldClaimerSlipstreamExtension } from "../../../../utils/extensions/YieldClaimerSlipstreamExtension.sol";
import { Slipstream_Fuzz_Test } from "../../base/Slipstream/_Slipstream.fuzz.t.sol";

/**
 * @notice Common logic needed by all "YieldClaimerSlipstream" fuzz tests.
 */
abstract contract YieldClaimerSlipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    YieldClaimerSlipstreamExtension internal yieldClaimer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Slipstream_Fuzz_Test) {
        Slipstream_Fuzz_Test.setUp();

        // Deploy test contract.
        yieldClaimer = new YieldClaimerSlipstreamExtension(
            users.owner,
            address(factory),
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );
    }
}
