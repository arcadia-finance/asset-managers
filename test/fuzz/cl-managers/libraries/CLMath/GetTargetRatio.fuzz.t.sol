/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getTargetRatio" of contract "CLMath".
 */
contract GetTargetRatio_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(CLMath_Fuzz_Test) {
        CLMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getTargetRatio_OverflowPriceX96(
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper
    ) public {
        // Given: sqrtPrice is bigger than type(uint128).max -> overflow.
        sqrtPrice = bound(sqrtPrice, uint256(type(uint128).max) + 1, TickMath.MAX_SQRT_PRICE - 1);

        // And: sqrtRatioLower is smaller than sqrtPrice.
        sqrtRatioLower = bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, sqrtPrice - 1);

        // And: sqrtRatioUpper is bigger than sqrtPrice.
        sqrtRatioUpper = bound(sqrtRatioUpper, sqrtPrice + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling _getTargetRatio().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
    }

    function testFuzz_Success_getTargetRatio(uint256 sqrtPrice, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        public
        view
    {
        // Given: sqrtPrice is smaller than type(uint128).max.
        sqrtPrice = bound(sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, uint256(type(uint128).max));

        // And: sqrtRatioLower is smaller than sqrtPrice.
        sqrtRatioLower = bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, sqrtPrice - 1);

        // And: sqrtRatioUpper is bigger than sqrtPrice.
        sqrtRatioUpper = bound(sqrtRatioUpper, sqrtPrice + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling _getTargetRatio().
        uint256 targetRatio = cLMath.getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);

        // Then: It should return the correct value.
        uint256 numerator = sqrtPrice - sqrtRatioLower;
        uint256 denominator = 2 * sqrtPrice - sqrtRatioLower - sqrtPrice ** 2 / sqrtRatioUpper;
        uint256 targetRatioExpected = numerator * 1e18 / denominator;
        assertEq(targetRatio, targetRatioExpected);
    }
}
