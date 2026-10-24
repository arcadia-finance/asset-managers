/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalancerMetadexCL_Fuzz_Test } from "./_RebalancerMetadexCL.fuzz.t.sol";
import { RebalancerSlipstreamExtension } from "../../../../utils/extensions/RebalancerSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerSlipstream", on Metadex CL.
 */
contract Constructor_RebalancerMetadexCL_Fuzz_Test is RebalancerMetadexCL_Fuzz_Test {
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
        RebalancerSlipstreamExtension rebalancer_ = new RebalancerSlipstreamExtension(
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

        assertEq(rebalancer_.owner(), owner_);
        assertEq(rebalancer_.guardian(), guardian_);
    }
}
