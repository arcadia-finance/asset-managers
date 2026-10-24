/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { YieldClaimerMetadexCL_Fuzz_Test } from "./_YieldClaimerMetadexCL.fuzz.t.sol";
import { YieldClaimerSlipstreamExtension } from "../../../../utils/extensions/YieldClaimerSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimerSlipstream", on Metadex CL.
 */
contract Constructor_YieldClaimerMetadexCL_Fuzz_Test is YieldClaimerMetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    // forge-lint: disable-next-item(empty-block)
    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address guardian_, address arcadiaFactory) public {
        YieldClaimerSlipstreamExtension yieldClaimer_ = new YieldClaimerSlipstreamExtension(
            owner_,
            guardian_,
            arcadiaFactory,
            address(metadex03PositionManager),
            address(metadex03CLFactory),
            metadex03PoolImplementation,
            receiptToken,
            address(stakedMetadex03CLAM),
            wrappedStakedMetadexCL
        );

        assertEq(yieldClaimer_.owner(), owner_);
        assertEq(yieldClaimer_.guardian(), guardian_);
    }
}
