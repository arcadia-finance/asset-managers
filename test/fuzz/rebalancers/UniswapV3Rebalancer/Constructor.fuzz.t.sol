/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "UniswapV3Rebalancer".
 */
contract Constructor_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(uint256 maxTolerance, uint256 maxInitiatorFee) public {
        vm.prank(users.owner);
        UniswapV3Rebalancer rebalancer_ = new UniswapV3Rebalancer(maxTolerance, maxInitiatorFee);

        assertEq(rebalancer_.MAX_TOLERANCE(), maxTolerance);
        assertEq(rebalancer.MAX_INITIATOR_FEE(), maxInitiatorFee);
    }
}
