/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CLMath } from "../../../../../src/cl-managers/libraries/CLMath.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmountIn" of contract "CLMath".
 */
contract GetAmountIn_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(CLMath_Fuzz_Test) {
        CLMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmountIn_OverflowPriceX96(
        uint256 sqrtPrice,
        bool zeroToOne,
        uint256 amountOut,
        uint256 fee
    ) public {
        // Given: sqrtPrice is bigger than type(uint128).max -> overflow.
        sqrtPrice = bound(sqrtPrice, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountIn(sqrtPrice, zeroToOne, amountOut, fee);
    }

    function testFuzz_Revert_getAmountIn_ZeroToOne_OverflowFullMath(uint256 sqrtPrice, uint256 amountOut, uint256 fee)
        public
    {
        // Given: sqrtPrice is smaller than type(uint128).max
        sqrtPrice = bound(sqrtPrice, 0, FixedPoint96.Q96 - 1);

        // And: amountOut is too small.
        amountOut = bound(
            amountOut, FullMath.mulDivRoundingUp(type(uint256).max, sqrtPrice ** 2, CLMath.Q192) + 1, type(uint256).max
        );

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountIn(sqrtPrice, true, amountOut, fee);
    }

    function testFuzz_Revert_getAmountIn_OneToZero_OverflowFullMath(uint256 sqrtPrice, uint256 amountOut, uint256 fee)
        public
    {
        // Given: sqrtPrice is smaller than type(uint128).max, but bigger than Q96.
        sqrtPrice = bound(sqrtPrice, FixedPoint96.Q96 + 1, type(uint128).max);

        // And: amountOut is too big.
        amountOut = bound(
            amountOut, FullMath.mulDivRoundingUp(type(uint256).max, CLMath.Q192, sqrtPrice ** 2) + 1, type(uint256).max
        );

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        cLMath.getAmountIn(sqrtPrice, false, amountOut, fee);
    }

    function testFuzz_Success_getAmountIn_ZeroToOne(uint256 sqrtPrice, uint256 amountOut, uint256 fee) public {
        // Given: sqrtPrice is smaller than type(uint128).max, but bigger than 0.
        sqrtPrice = bound(sqrtPrice, 1, type(uint128).max);

        // And: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: amountOut is not too big.
        if (sqrtPrice < FixedPoint96.Q96 * 1e9) {
            amountOut = bound(amountOut, 0, FullMath.mulDiv(type(uint256).max / 1e18, sqrtPrice ** 2, CLMath.Q192));
        }

        // When: Calling _getAmountIn().
        uint256 amountIn = cLMath.getAmountIn(sqrtPrice, true, amountOut, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = FullMath.mulDiv(amountOut, CLMath.Q192, sqrtPrice ** 2);
        uint256 amountInExpected = amountInWithoutFees * 1e18 / (1e18 - fee);
        assertEq(amountIn, amountInExpected);
    }

    function testFuzz_Success_getAmountIn_OneToZero(uint256 sqrtPrice, uint256 amountOut, uint256 fee) public {
        // Given: sqrtPrice is smaller than type(uint128).max, but bigger than Q96.
        sqrtPrice = bound(sqrtPrice, 0, type(uint128).max);

        // And: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: amountOut is not too big.
        if (sqrtPrice * 1e9 > FixedPoint96.Q96) {
            amountOut = bound(amountOut, 0, FullMath.mulDiv(type(uint256).max / 1e18, CLMath.Q192, sqrtPrice ** 2));
        }

        // When: Calling _getAmountIn().
        uint256 amountIn = cLMath.getAmountIn(sqrtPrice, false, amountOut, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = FullMath.mulDiv(amountOut, sqrtPrice ** 2, CLMath.Q192);
        uint256 amountInExpected = amountInWithoutFees * 1e18 / (1e18 - fee);
        assertEq(amountIn, amountInExpected);
    }
}
