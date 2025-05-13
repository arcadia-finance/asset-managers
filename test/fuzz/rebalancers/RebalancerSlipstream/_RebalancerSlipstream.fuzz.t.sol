/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerSlipstreamExtension } from "../../../utils/extensions/RebalancerSlipstreamExtension.sol";
import { Slipstream_Fuzz_Test } from "../../base/Slipstream/_Slipstream.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerSlipstream" fuzz tests.
 */
abstract contract RebalancerSlipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerSlipstreamExtension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Slipstream_Fuzz_Test) {
        Slipstream_Fuzz_Test.setUp();

        // Deploy test contract.
        rebalancer = new RebalancerSlipstreamExtension(
            address(factory),
            MAX_FEE,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );
    }
}
