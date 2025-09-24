/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "IsPositionManager" of contract "UniswapV4".
 */
contract IsPositionManager_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPositionManager_False(address positionManager) public view {
        // Given: positionManager is not the UniswapV4 Position Manager.
        vm.assume(positionManager != address(positionManagerV4));

        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(positionManager);

        // Then: It should return "false".
        assertFalse(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True() public view {
        // Given: positionManager is the UniswapV4 Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = base.isPositionManager(address(positionManagerV4));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }
}
