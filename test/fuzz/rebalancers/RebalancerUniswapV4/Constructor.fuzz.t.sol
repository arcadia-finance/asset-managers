/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerUniswapV4".
 */
contract Constructor_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio)
        public
    {
        vm.prank(users.owner);
        RebalancerUniswapV4 rebalancer_ = new RebalancerUniswapV4(maxTolerance, maxInitiatorFee, maxSlippageRatio);

        assertEq(rebalancer_.MAX_TOLERANCE(), maxTolerance);
        assertEq(rebalancer_.MAX_INITIATOR_FEE(), maxInitiatorFee);
        assertEq(rebalancer_.MIN_LIQUIDITY_RATIO(), maxSlippageRatio);
    }
}
