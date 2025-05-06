/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "IsPositionManager" of contract "RebalancerSlipstream".
 */
contract IsPositionManager_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPositionManager_False(address positionManager) public {
        // Given: positionManager is not the Slipstream Position Manager.
        vm.assume(positionManager != address(slipstreamPositionManager));
        vm.assume(positionManager != address(stakedSlipstreamAM));
        vm.assume(positionManager != address(wrappedStakedSlipstream));

        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(positionManager);

        // Then: It should return "false".
        assertFalse(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_SlipstreamPositionManager() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(address(slipstreamPositionManager));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_StakedSlipstreamAM() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(address(stakedSlipstreamAM));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_WrappedStakedSlipstream() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(address(wrappedStakedSlipstream));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }
}
