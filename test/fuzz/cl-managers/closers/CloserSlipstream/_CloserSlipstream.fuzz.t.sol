/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserSlipstreamExtension } from "../../../../utils/extensions/CloserSlipstreamExtension.sol";
import { Slipstream_Fuzz_Test } from "../../base/Slipstream/_Slipstream.fuzz.t.sol";

/**
 * @notice Common logic needed by all "CloserSlipstream" fuzz tests.
 */
abstract contract CloserSlipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_CLAIM_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CloserSlipstreamExtension internal closer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Slipstream_Fuzz_Test) {
        Slipstream_Fuzz_Test.setUp();

        // Deploy test contract.
        closer = new CloserSlipstreamExtension(
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
