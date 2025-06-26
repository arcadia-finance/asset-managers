/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CompounderSlipstreamExtension } from "../../../../utils/extensions/CompounderSlipstreamExtension.sol";
import { Slipstream_Fuzz_Test } from "../../base/Slipstream/_Slipstream.fuzz.t.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "CompounderSlipstream" fuzz tests.
 */
abstract contract CompounderSlipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CompounderSlipstreamExtension internal compounder;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Slipstream_Fuzz_Test) {
        Slipstream_Fuzz_Test.setUp();

        // Deploy test contract.
        compounder = new CompounderSlipstreamExtension(
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
