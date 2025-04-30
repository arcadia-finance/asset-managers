/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CLMath } from "../../../../src/libraries/CLMath.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getSpotValue" of contract "CLMath".
 */
contract GetSpotValue_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(CLMath_Fuzz_Test) {
        CLMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getSpotValue_OverflowPriceX96(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountIn)
        public
    {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Calling _getSpotValue().
        // Then: It should revert.
        vm.expectRevert(stdError.arithmeticError);
        cLMath.getSpotValue(sqrtPriceX96, zeroToOne, amountIn);
    }

    function testFuzz_Revert_getSpotValue_ZeroToOne_OverflowFullMath(uint256 sqrtPriceX96, uint256 amountIn) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than Q96.
        sqrtPriceX96 = bound(sqrtPriceX96, FixedPoint96.Q96 + 1, type(uint128).max);

        // And: amountIn is too big.
        amountIn = bound(
            amountIn,
            FullMath.mulDivRoundingUp(type(uint256).max, CLMath.Q192, sqrtPriceX96 ** 2) + 1,
            type(uint256).max
        );

        // When: Calling _getSpotValue().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getSpotValue(sqrtPriceX96, true, amountIn);
    }

    function testFuzz_Revert_getSpotValue_OneToZero_OverflowFullMath(uint256 sqrtPriceX96, uint256 amountIn) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max
        sqrtPriceX96 = bound(sqrtPriceX96, 0, FixedPoint96.Q96 - 1);

        // And: amountIn is too small.
        amountIn = bound(
            amountIn,
            FullMath.mulDivRoundingUp(type(uint256).max, sqrtPriceX96 ** 2, CLMath.Q192) + 1,
            type(uint256).max
        );

        // When: Calling _getSpotValue().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getSpotValue(sqrtPriceX96, false, amountIn);
    }

    function testFuzz_Success_getSpotValue_ZeroToOne(uint256 sqrtPriceX96, uint256 amountIn) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than Q96.
        sqrtPriceX96 = bound(sqrtPriceX96, 0, type(uint128).max);

        // And: amountIn is not too big.
        if (sqrtPriceX96 > FixedPoint96.Q96) {
            amountIn = bound(amountIn, 0, FullMath.mulDiv(type(uint256).max, CLMath.Q192, sqrtPriceX96 ** 2));
        }

        // When: Calling _getSpotValue().
        uint256 amountOut = cLMath.getSpotValue(sqrtPriceX96, true, amountIn);

        // Then: It should return the correct value.
        assertEq(amountOut, FullMath.mulDiv(amountIn, sqrtPriceX96 ** 2, CLMath.Q192));
    }

    function testFuzz_Success_getSpotValue_OneToZero(uint256 sqrtPriceX96, uint256 amountIn) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than 0.
        sqrtPriceX96 = bound(sqrtPriceX96, 1, type(uint128).max);

        // And: amountIn is not too big.
        if (sqrtPriceX96 < FixedPoint96.Q96) {
            amountIn = bound(amountIn, 0, FullMath.mulDiv(type(uint256).max, sqrtPriceX96 ** 2, CLMath.Q192));
        }

        // When: Calling _getSpotValue().
        uint256 amountOut = cLMath.getSpotValue(sqrtPriceX96, false, amountIn);

        // Then: It should return the correct value.
        assertEq(amountOut, FullMath.mulDiv(amountIn, CLMath.Q192, sqrtPriceX96 ** 2));
    }
}
