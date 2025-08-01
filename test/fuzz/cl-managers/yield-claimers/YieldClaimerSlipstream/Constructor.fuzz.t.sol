/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimerSlipstream_Fuzz_Test } from "./_YieldClaimerSlipstream.fuzz.t.sol";
import { YieldClaimerSlipstreamExtension } from "../../../../utils/extensions/YieldClaimerSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimerSlipstream".
 */
contract Constructor_YieldClaimerSlipstream_Fuzz_Test is YieldClaimerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        YieldClaimerSlipstreamExtension yieldClaimer_ = new YieldClaimerSlipstreamExtension(
            owner_,
            arcadiaFactory,
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );

        assertEq(yieldClaimer_.owner(), owner_);
        assertEq(address(yieldClaimer_.ARCADIA_FACTORY()), arcadiaFactory);
    }
}
