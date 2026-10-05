/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { QuadraticMathExtension } from "../../../../utils/extensions/QuadraticMathExtension.sol";

/**
 * @notice Common logic needed by all "QuadraticMath" fuzz tests.
 */
abstract contract QuadraticMath_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    QuadraticMathExtension internal quadraticMath;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        quadraticMath = new QuadraticMathExtension();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function getResidual(int256 a, uint256 b, uint256 c, uint256 x) internal pure returns (uint256 residual) {
        uint256 quadraticTerm = FullMath.mulDiv(FullMath.mulDiv(uint256(a < 0 ? -a : a), x, 1 << 192), x, 1 << 192);
        uint256 linearTerm = FullMath.mulDiv(b, x, 1 << 192);
        int256 signedResidual =
            (a < 0 ? -int256(quadraticTerm) : int256(quadraticTerm)) - int256(linearTerm) + int256(c);
        residual = signedResidual < 0 ? uint256(-signedResidual) : uint256(signedResidual);
    }

    function getResidualTolerance(int256 a, uint256 b, uint256 c, uint256 x) internal pure returns (uint256 tolerance) {
        uint256 absA = uint256(a < 0 ? -a : a);
        uint256 bx = FullMath.mulDiv(b, x, 1 << 192);
        uint256 ax = FullMath.mulDiv(absA, x, 1 << 192);
        tolerance = (bx >> 96) + ((bx + ax) >> 191) + (b >> 191) + (absA >> 191) + (c >> 191)
            + (FullMath.mulDiv(ax, x, 1 << 192) >> 190) + 8;
    }
}
