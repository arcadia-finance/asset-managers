/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CompounderSlipstream_Fuzz_Test } from "./_CompounderSlipstream.fuzz.t.sol";
import { CompounderSlipstreamExtension } from "../../../utils/extensions/CompounderSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CompounderSlipstream".
 */
contract Constructor_CompounderSlipstream_Fuzz_Test is CompounderSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address arcadiaFactory) public {
        vm.prank(users.owner);
        CompounderSlipstreamExtension compounder_ = new CompounderSlipstreamExtension(
            arcadiaFactory,
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );

        assertEq(address(compounder_.ARCADIA_FACTORY()), arcadiaFactory);
    }
}
