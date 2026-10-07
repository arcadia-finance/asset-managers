/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { QuadraticMath_Fuzz_Test } from "./_QuadraticMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getRoot" of contract "QuadraticMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetRoot_QuadraticMath_Fuzz_Test is QuadraticMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        QuadraticMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getRoot_ZeroQuadraticCoefficient(uint256 b, uint256 c) public view {
        // Given: A linear coefficient between the width of one tick and 2^254.
        b = bound(b, 1 << 177, 1 << 254);

        // And: The constant coefficient is positive, at most 2^252 and 2^60 times b.
        c = bound(c, 1, b < 1 << 192 ? b << 60 : 1 << 252);

        // When: Calling _getRoot() with a zero quadratic coefficient.
        uint256 x = quadraticMath.getRoot(0, int256(b), int256(c));

        // Then: x is c * 2^192 / b, rounded down.
        assertEq(x, FullMath.mulDiv(c, 1 << 192, b));
    }

    function testFuzz_Success_getRoot_NonNegativeQuadraticCoefficient(uint256 a, uint256 b, uint256 c) public view {
        // Given: A linear coefficient between the width of one tick and 2^254.
        b = bound(b, 1 << 177, 1 << 254);

        // And: A nonnegative quadratic coefficient, at most 2^15 * b and 2^253.
        a = bound(a, 0, b < 1 << 238 ? b << 15 : 1 << 253);

        // And: A positive constant below b / 2, with 4ac at most b² * (1 − 2^-62).
        {
            uint256 maxC = b >> 1;
            if (a > b >> 1) {
                uint256 maxCDiscriminant = FullMath.mulDiv(b, b - (b >> 62), a << 2);
                if (maxCDiscriminant < maxC) maxC = maxCDiscriminant;
            }
            c = bound(c, 1, maxC);
        }

        // When: Calling _getRoot().
        uint256 x = quadraticMath.getRoot(int256(a), int256(b), int256(c));

        // Then: x is at most 2c / b.
        assertLe(x, FullMath.mulDiv(c, 1 << 193, b));

        // And: The residual a * x² − b * x + c is within the tolerance of zero.
        assertLe(getResidual(int256(a), b, c, x), getResidualTolerance(int256(a), b, c, x));
    }

    function testFuzz_Success_getRoot_NegativeQuadraticCoefficient(uint256 a, uint256 b, uint256 c) public view {
        // Given: A linear coefficient between the width of one tick and 2^254.
        b = bound(b, 1 << 177, 1 << 254);

        // And: A negative quadratic coefficient, |a| at most 2^15 * b and 2^253.
        a = bound(a, 1, b < 1 << 238 ? b << 15 : 1 << 253);

        // And: A positive constant at most 2^252 and 2^60 * b, |4ac / b²| at most 2^62.
        {
            uint256 maxC = b < 1 << 192 ? b << 60 : 1 << 252;
            if (a > b) {
                uint256 maxCDiscriminant = FullMath.mulDiv(b, b, a);
                if (maxCDiscriminant < maxC >> 60) maxC = maxCDiscriminant << 60;
            }
            c = bound(c, 1, maxC);
        }

        // When: Calling _getRoot().
        uint256 x = quadraticMath.getRoot(-int256(a), int256(b), int256(c));

        // Then: x is at most 2c / b.
        assertLe(x, FullMath.mulDiv(c, 1 << 193, b));

        // And: The residual a * x² − b * x + c is within the tolerance of zero.
        assertLe(getResidual(-int256(a), b, c, x), getResidualTolerance(-int256(a), b, c, x));
    }

    function testFuzz_Success_getRoot_NegativeQuadraticCoefficient_ExactSquareRoot(uint256 b, uint256 increment)
        public
        view
    {
        // Given: The linear coefficient is a power of two between 2^191 and 2^253.
        uint256 exponent = bound(b, 191, 253);
        b = 1 << exponent;

        // And: The constant coefficient is half the linear coefficient.
        uint256 c = b >> 1;

        // And: A negative a with √(b² − 4ac) / b exactly 1 + increment / 2^95.
        increment = bound(increment, 1, 1 << 93);
        uint256 a = ((increment << 96) + increment * increment) << (exponent - 191);

        // When: Calling _getRoot().
        uint256 x = quadraticMath.getRoot(-int256(a), int256(b), int256(c));

        // Then: x is 2c / (b + √(b² − 4ac)), rounded down.
        assertEq(x, FullMath.mulDiv(2 * c, 1 << 192, b + FullMath.mulDiv(b, (1 << 96) + 2 * increment, 1 << 96)));
    }
}
