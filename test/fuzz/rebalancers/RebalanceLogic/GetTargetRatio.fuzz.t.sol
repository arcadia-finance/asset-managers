/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceLogic } from "../../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalanceLogic_Fuzz_Test } from "./_RebalanceLogic.fuzz.t.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getTargetRatio" of contract "RebalanceLogic".
 */
contract GetTargetRatio_RebalanceLogic_Fuzz_Test is RebalanceLogic_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalanceLogic_Fuzz_Test) {
        RebalanceLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getTargetRatio_OverflowPriceX96(
        uint256 sqrtPriceX96,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper
    ) public {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, TickMath.MAX_SQRT_PRICE - 1);

        // And: sqrtRatioLower is smaller than sqrtPriceX96.
        sqrtRatioLower = bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, sqrtPriceX96 - 1);

        // And: sqrtRatioUpper is bigger than sqrtPriceX96.
        sqrtRatioUpper = bound(sqrtRatioUpper, sqrtPriceX96 + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling _getTargetRatio().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        rebalanceLogic.getTargetRatio(sqrtPriceX96, sqrtRatioLower, sqrtRatioUpper);
    }

    function testFuzz_Success_getTargetRatio(uint256 sqrtPriceX96, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        public
    {
        // Given: sqrtPriceX96 is smaller than type(uint128).max.
        sqrtPriceX96 = bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, uint256(type(uint128).max));

        // And: sqrtRatioLower is smaller than sqrtPriceX96.
        sqrtRatioLower = bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, sqrtPriceX96 - 1);

        // And: sqrtRatioUpper is bigger than sqrtPriceX96.
        sqrtRatioUpper = bound(sqrtRatioUpper, sqrtPriceX96 + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling _getTargetRatio().
        uint256 targetRatio = rebalanceLogic.getTargetRatio(sqrtPriceX96, sqrtRatioLower, sqrtRatioUpper);

        // Then: It should return the correct value.
        uint256 numerator = sqrtPriceX96 - sqrtRatioLower;
        uint256 denominator = 2 * sqrtPriceX96 - sqrtRatioLower - sqrtPriceX96 ** 2 / sqrtRatioUpper;
        uint256 targetRatioExpected = numerator * 1e18 / denominator;
        assertEq(targetRatio, targetRatioExpected);
    }
}
