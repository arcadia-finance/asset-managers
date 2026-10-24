/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexCL_Fuzz_Test } from "../../base/MetadexCL/_MetadexCL.fuzz.t.sol";
import { RebalancerSlipstreamExtension } from "../../../../utils/extensions/RebalancerSlipstreamExtension.sol";
import { RouterTrampoline } from "../../../../../src/cl-managers/RouterTrampoline.sol";

/**
 * @notice Common logic needed by all "RebalancerMetadexCL" fuzz tests.
 */
abstract contract RebalancerMetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterTrampoline internal routerTrampoline;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerSlipstreamExtension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(MetadexCL_Fuzz_Test) {
        MetadexCL_Fuzz_Test.setUp();

        // Deploy Router Trampoline.
        routerTrampoline = new RouterTrampoline();

        // Deploy test contract.
        rebalancer = new RebalancerSlipstreamExtension(
            users.owner,
            users.guardian,
            address(factory),
            address(routerTrampoline),
            address(metadex03PositionManager),
            address(metadex03CLFactory),
            metadex03PoolImplementation,
            receiptToken,
            address(stakedMetadex03CLAM),
            wrappedStakedMetadexCL
        );
    }
}
