/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CLMath } from "../../../../src/libraries/CLMath.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmountOut" of contract "CLMath".
 */
contract GetAmountOut_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(CLMath_Fuzz_Test) {
        CLMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmountOut_OverflowPriceX96(
        uint256 sqrtPrice,
        bool zeroToOne,
        uint256 amountIn,
        uint256 fee
    ) public {
        // Given: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: amountIn is not too big.
        amountIn = bound(amountIn, 0, type(uint256).max / (1e18 - fee));

        // And: sqrtPrice is bigger than type(uint128).max -> overflow.
        sqrtPrice = bound(sqrtPrice, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Calling _getAmountOut().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountOut(sqrtPrice, zeroToOne, amountIn, fee);
    }

    function testFuzz_Revert_getAmountOut_ZeroToOne_OverflowFullMath(uint256 sqrtPrice, uint256 amountIn, uint256 fee)
        public
    {
        // Given: fee is smaller than 100%.
        fee = 0;

        // And: amountIn is not too big for first division.
        amountIn = bound(amountIn, 0, type(uint256).max / (1e18 - fee));

        // And: sqrtPrice is smaller than type(uint128).max, but bigger than Q96.
        sqrtPrice = bound(sqrtPrice, FixedPoint96.Q96 + 1, type(uint128).max);

        // And: amountIn is too big.
        amountIn = bound(
            amountIn, FullMath.mulDivRoundingUp(type(uint256).max, CLMath.Q192, sqrtPrice ** 2) + 1, type(uint256).max
        );

        // When: Calling _getAmountOut().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountOut(sqrtPrice, true, amountIn, fee);
    }

    function testFuzz_Revert_getAmountOut_OneToZero_OverflowFullMath(uint256 sqrtPrice, uint256 amountIn, uint256 fee)
        public
    {
        // Given: fee is smaller than 100%.
        fee = 0;

        // And: amountIn is not too big for first division.
        amountIn = bound(amountIn, 0, type(uint256).max / (1e18 - fee));

        // And: sqrtPrice is smaller than type(uint128).max
        sqrtPrice = bound(sqrtPrice, 0, FixedPoint96.Q96 - 1);

        // And: amountIn is too small.
        amountIn = bound(
            amountIn, FullMath.mulDivRoundingUp(type(uint256).max, sqrtPrice ** 2, CLMath.Q192) + 1, type(uint256).max
        );

        // When: Calling _getAmountOut().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountOut(sqrtPrice, false, amountIn, fee);
    }

    function testFuzz_Success_getAmountOut_ZeroToOne(uint256 sqrtPrice, uint256 amountIn, uint256 fee) public {
        // Given: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: sqrtPrice is smaller than type(uint128).max, but bigger than Q96.
        sqrtPrice = bound(sqrtPrice, 0, type(uint128).max);

        // And: amountIn is not too big for first division.
        amountIn = bound(amountIn, 0, type(uint256).max / (1e18 - fee));

        // And: amountIn is not too big.
        if (sqrtPrice > FixedPoint96.Q96) {
            amountIn = bound(amountIn, 0, FullMath.mulDiv(type(uint256).max, CLMath.Q192, sqrtPrice ** 2));
        }

        // When: Calling _getAmountOut().
        uint256 amountOut = cLMath.getAmountOut(sqrtPrice, true, amountIn, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = amountIn * (1e18 - fee) / 1e18;
        uint256 amountOutExpected = FullMath.mulDiv(amountInWithoutFees, sqrtPrice ** 2, CLMath.Q192);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getAmountOut_OneToZero(uint256 sqrtPrice, uint256 amountIn, uint256 fee) public {
        // Given: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: sqrtPrice is smaller than type(uint128).max, but bigger than 0.
        sqrtPrice = bound(sqrtPrice, 1, type(uint128).max);

        // And: amountIn is not too big for first division.
        amountIn = bound(amountIn, 0, type(uint256).max / (1e18 - fee));

        // And: amountIn is not too big.
        if (sqrtPrice < FixedPoint96.Q96) {
            amountIn = bound(amountIn, 0, FullMath.mulDiv(type(uint256).max, sqrtPrice ** 2, CLMath.Q192));
        }

        // When: Calling _getAmountOut().
        uint256 amountOut = cLMath.getAmountOut(sqrtPrice, false, amountIn, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = amountIn * (1e18 - fee) / 1e18;
        uint256 amountOutExpected = FullMath.mulDiv(amountInWithoutFees, CLMath.Q192, sqrtPrice ** 2);
        assertEq(amountOut, amountOutExpected);
    }
}
