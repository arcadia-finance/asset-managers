/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserSlipstream_Fuzz_Test } from "./_CloserSlipstream.fuzz.t.sol";
import { CloserSlipstreamExtension } from "../../../../utils/extensions/CloserSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CloserSlipstream".
 */
contract Constructor_CloserSlipstream_Fuzz_Test is CloserSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        CloserSlipstreamExtension closer_ = new CloserSlipstreamExtension(
            owner_,
            arcadiaFactory,
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );

        assertEq(closer_.owner(), owner_);
    }
}
