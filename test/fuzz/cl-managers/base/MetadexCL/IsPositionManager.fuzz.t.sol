/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isPositionManager" of contract "Slipstream", on Metadex CL.
 */
contract IsPositionManager_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPositionManager_False(address positionManager) public view {
        // Given: positionManager is not one of the Metadex CL position managers.
        vm.assume(positionManager != address(metadex03PositionManager));
        vm.assume(positionManager != address(stakedMetadex03CLAM));
        vm.assume(positionManager != wrappedStakedMetadexCL);

        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(positionManager);

        // Then: It should return "false".
        assertFalse(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True_MetadexPositionManager() public view {
        // Given: positionManager is the Metadex CL Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(metadex03PositionManager));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_isPositionManager_True_StakedMetadexCLAM() public view {
        // Given: positionManager is the Staked Metadex CL Asset Module.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(stakedMetadex03CLAM));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_isPositionManager_True_WrappedStakedMetadexCL() public view {
        // Given: positionManager is the Wrapped Staked Metadex CL wrapper.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(wrappedStakedMetadexCL);

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }
}
