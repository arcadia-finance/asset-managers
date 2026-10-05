/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPoint96 } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";

// forge-lint: disable-next-item(unsafe-typecast)
library QuadraticMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                              ROOT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the smallest positive root of a * x² − b * x + c = 0, for b and c strictly positive.
     * @param a The quadratic coefficient, with 192 binary precision, its sign selecting the value under the square root.
     * @param b The linear coefficient, with 192 binary precision.
     * @param c The constant coefficient, with 192 binary precision.
     * @return x The smallest positive root, with 192 binary precision.
     * @dev The smallest positive root is calculated as:
     *     x = 2c / (b + √[b² − 4ac])
     *     The alternative form (b − √[b² − 4ac]) / (2a) subtracts two numbers that are nearly equal when c is
     *     small, which causes a loss of precision. Adding them instead avoids that loss.
     * @dev The discriminant is taken relative to b², so b² is never calculated at full width:
     *     w = 4ac / b² = 4 * a * (c / b) / b
     *     √[b² − 4ac] = b * √[1 − w]
     *     => x = 2 * (c / b) / (1 + √[1 − w])
     *     A negative a flips the sign of w, so the value under the square root becomes 1 + |w| and stays positive.
     * @dev Requires c / b below 2^63, w at most one for a nonnegative a, and |w| below 2^63 for a negative a.
     */
    function _getRoot(int256 a, int256 b, int256 c) internal pure returns (uint256 x) {
        unchecked {
            // The discriminant and the root are both expressed in ratio = c / b.
            uint256 ratio = uint256(c).fullMulDivUnchecked(1 << 192, uint256(b)); // 192 binary precision.
            // The discriminant relative to b², on the absolute value of a: w = 4 * a * (c / b) / b
            uint256 discriminant = 4 * uint256(a < 0 ? -a : a).fullMulDivUnchecked(ratio, uint256(b)); // 192 binary precision.

            uint256 discriminantRoot;
            if (a < 0) {
                // Sqrt halves the binary precision: √[1 + w]
                discriminantRoot = ((1 << 192) + discriminant).sqrt(); // 96 binary precision.
            } else {
                // Sqrt halves the binary precision: √[1 − w]
                discriminantRoot = ((1 << 192) - discriminant).sqrt(); // 96 binary precision.
            }

            // The smallest positive root, in the form that avoids the loss of precision: x = 2 * (c / b) / (1 + √[1 − w])
            x = (2 * ratio).fullMulDivUnchecked(FixedPoint96.Q96, FixedPoint96.Q96 + discriminantRoot); // 192 binary precision.
        }
    }
}
