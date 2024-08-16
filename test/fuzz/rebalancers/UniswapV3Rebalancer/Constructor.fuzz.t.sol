/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
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
    function testFuzz_Revert_Constructor_UnderflowTolerance(uint256 tolerance, uint256 liquidityTreshold) public {
        tolerance = bound(tolerance, 1e18 + 1, type(uint256).max);

        vm.prank(users.owner);
        vm.expectRevert(stdError.arithmeticError);
        new UniswapV3Rebalancer(tolerance, liquidityTreshold);
    }

    function testFuzz_Success_Constructor(uint256 tolerance, uint256 liquidityTreshold) public {
        tolerance = bound(tolerance, 0, 1e18);

        vm.prank(users.owner);
        UniswapV3Rebalancer rebalancer_ = new UniswapV3Rebalancer(tolerance, liquidityTreshold);

        assertEq(rebalancer_.LIQUIDITY_TRESHOLD(), liquidityTreshold);

        uint256 lowerDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        uint256 upperDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);

        assertEq(rebalancer_.LOWER_SQRT_PRICE_DEVIATION(), lowerDeviation);
        assertEq(rebalancer_.UPPER_SQRT_PRICE_DEVIATION(), upperDeviation);
    }
}
