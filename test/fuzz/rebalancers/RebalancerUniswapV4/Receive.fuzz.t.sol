/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "receive" of contract "RebalancerUniswapV4".
 */
contract Receive_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniswapV4_Fuzz_Test) {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_receive(uint256 value) public {
        deal(address(poolManager), value);

        vm.prank(address(poolManager));
        (bool success, bytes memory data) = address(rebalancer).call{ value: value }(new bytes(0));

        assertTrue(success);
        assertEq(data, bytes(""));
    }
}
