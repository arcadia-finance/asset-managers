/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CompounderMetadexCL_Fuzz_Test } from "./_CompounderMetadexCL.fuzz.t.sol";
import { CompounderSlipstreamExtension } from "../../../../utils/extensions/CompounderSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CompounderSlipstream", on Metadex CL.
 */
contract Constructor_CompounderMetadexCL_Fuzz_Test is CompounderMetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    // forge-lint: disable-next-item(empty-block)
    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(
        address owner_,
        address guardian_,
        address arcadiaFactory,
        address routerTrampoline_
    ) public {
        CompounderSlipstreamExtension compounder_ = new CompounderSlipstreamExtension(
            owner_,
            guardian_,
            arcadiaFactory,
            routerTrampoline_,
            address(metadex03PositionManager),
            address(metadex03CLFactory),
            metadex03PoolImplementation,
            receiptToken,
            address(stakedMetadex03CLAM),
            wrappedStakedMetadexCL
        );

        assertEq(compounder_.owner(), owner_);
        assertEq(compounder_.guardian(), guardian_);
    }
}
