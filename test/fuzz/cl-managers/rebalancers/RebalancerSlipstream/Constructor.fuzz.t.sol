/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";
import { RebalancerSlipstreamExtension } from "../../../../utils/extensions/RebalancerSlipstreamExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerSlipstream".
 */
contract Constructor_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        RebalancerSlipstreamExtension rebalancer_ = new RebalancerSlipstreamExtension(
            owner_,
            arcadiaFactory,
            routerTrampoline_,
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );

        assertEq(rebalancer_.owner(), owner_);
        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(rebalancer_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
