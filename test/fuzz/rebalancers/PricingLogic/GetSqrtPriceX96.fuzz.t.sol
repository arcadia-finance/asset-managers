/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { PricingLogic_Fuzz_Test } from "./_PricingLogic.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPriceX96" of contract "PricingLogic".
 */
contract GetSqrtPriceX96_PricingLogic_Fuzz_Test is PricingLogic_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(PricingLogic_Fuzz_Test) {
        PricingLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPriceX96_ZeroPriceToken1(uint256 priceToken0) public {
        // Test-case.
        uint256 priceToken1 = 0;

        uint256 expectedSqrtPriceX96 = TickMath.MAX_SQRT_PRICE;
        uint256 actualSqrtPriceX96 = pricingLogic.getSqrtPriceX96(priceToken0, priceToken1);

        assertEq(actualSqrtPriceX96, expectedSqrtPriceX96);
    }

    function testFuzz_Success_getSqrtPriceX96_Overflow(uint256 priceToken0, uint256 priceToken1) public {
        // Avoid divide by 0, which is already checked in earlier in function.
        priceToken1 = bound(priceToken1, 1, type(uint256).max);
        // Function will overFlow, not realistic.
        priceToken0 = bound(priceToken0, 0, type(uint256).max / 1e28);

        // Cast to uint160 overflows (test-case).
        vm.assume(priceToken0 / priceToken1 >= 2 ** 128);

        uint256 priceXd28 = priceToken0 * 1e28 / priceToken1;
        uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);

        uint256 expectedSqrtPriceX96 = sqrtPriceXd14 * 2 ** 96 / 1e14;
        uint256 actualSqrtPriceX96 = pricingLogic.getSqrtPriceX96(priceToken0, priceToken1);

        assertLt(actualSqrtPriceX96, expectedSqrtPriceX96);
    }

    function testFuzz_Success_getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public {
        // Avoid divide by 0, which is already checked in earlier in function.
        priceToken1 = bound(priceToken1, 1, type(uint256).max);
        // Function will overFlow, not realistic.
        priceToken0 = bound(priceToken0, 0, type(uint256).max / 1e28);
        // Cast to uint160 will overflow, not realistic.
        vm.assume(priceToken0 / priceToken1 < 2 ** 128);

        uint256 priceXd28 = priceToken0 * 1e28 / priceToken1;
        uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);

        uint256 expectedSqrtPriceX96 = sqrtPriceXd14 * 2 ** 96 / 1e14;
        uint256 actualSqrtPriceX96 = pricingLogic.getSqrtPriceX96(priceToken0, priceToken1);

        assertEq(actualSqrtPriceX96, expectedSqrtPriceX96);
    }
}
