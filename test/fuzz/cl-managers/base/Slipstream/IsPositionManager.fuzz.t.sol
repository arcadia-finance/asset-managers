/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Slipstream_Fuzz_Test } from "./_Slipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "IsPositionManager" of contract "Slipstream".
 */
contract IsPositionManager_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Slipstream_Fuzz_Test.setUp();
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
        bool isPositionManager = base.isPositionManager(positionManager);

        // Then: It should return "false".
        assertFalse(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_SlipstreamPositionManager() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(slipstreamPositionManager));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_StakedSlipstreamAM() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(stakedSlipstreamAM));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_WrappedStakedSlipstream() public {
        // Given: positionManager is the Slipstream Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(wrappedStakedSlipstream));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }
}
