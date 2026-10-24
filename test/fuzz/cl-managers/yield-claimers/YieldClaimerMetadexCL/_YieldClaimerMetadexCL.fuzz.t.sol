/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexCL_Fuzz_Test } from "../../base/MetadexCL/_MetadexCL.fuzz.t.sol";
import { YieldClaimerSlipstreamExtension } from "../../../../utils/extensions/YieldClaimerSlipstreamExtension.sol";

/**
 * @notice Common logic needed by all "YieldClaimerMetadexCL" fuzz tests.
 */
abstract contract YieldClaimerMetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    YieldClaimerSlipstreamExtension internal yieldClaimer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(MetadexCL_Fuzz_Test) {
        MetadexCL_Fuzz_Test.setUp();

        // Deploy test contract.
        yieldClaimer = new YieldClaimerSlipstreamExtension(
            users.owner,
            users.guardian,
            address(factory),
            address(metadex03PositionManager),
            address(metadex03CLFactory),
            metadex03PoolImplementation,
            receiptToken,
            address(stakedMetadex03CLAM),
            wrappedStakedMetadexCL
        );
    }
}
