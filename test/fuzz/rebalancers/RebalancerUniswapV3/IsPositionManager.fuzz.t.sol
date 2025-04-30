/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "IsPositionManager" of contract "RebalancerUniswapV3".
 */
contract IsPositionManager_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPositionManager_False(address positionManager) public {
        // Given: positionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(nonfungiblePositionManager));

        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(positionManager);

        // Then: It should return "false".
        assertFalse(isPositionManager);
    }

    function testFuzz_Success_isPositionManager_True() public {
        // Given: positionManager is the UniswapV3 Position Manager.
        // When: Calling isPositionManager.
        bool isPositionManager = rebalancer.isPositionManager(address(nonfungiblePositionManager));

        // Then: It should return "true".
        assertTrue(isPositionManager);
    }
}
