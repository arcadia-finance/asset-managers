/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getQuadraticCoefficients" of contract "RebalanceOptimizationMath".
 */
contract GetQuadraticCoefficients_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getQuadraticCoefficients_ZeroToOne_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is zero.
        assertEq(constantCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }

    function testFuzz_Success_getQuadraticCoefficients_ZeroToOne_Liquidity0Exceeds(SwapParams memory params)
        public
        view
    {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: liquidity0 exceeds liquidity1 by more than the rounding.
        givenValidBalancesBeyondMargin(params, true);

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is positive.
        assertGt(constantCoefficient, 0);

        // And: The linear coefficient is positive.
        assertGt(linearCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }

    function testFuzz_Success_getQuadraticCoefficients_ZeroToOne_Liquidity1Exceeds(SwapParams memory params)
        public
        view
    {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: liquidity1 exceeds liquidity0 by more than the rounding.
        givenValidBalancesBeyondMargin(params, false);

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is negative.
        assertLt(constantCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }

    function testFuzz_Success_getQuadraticCoefficients_OneToZero_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is zero.
        assertEq(constantCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }

    function testFuzz_Success_getQuadraticCoefficients_OneToZero_Liquidity0Exceeds(SwapParams memory params)
        public
        view
    {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: liquidity0 exceeds liquidity1 by more than the rounding.
        givenValidBalancesBeyondMargin(params, true);

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is positive.
        assertGt(constantCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }

    function testFuzz_Success_getQuadraticCoefficients_OneToZero_Liquidity1Exceeds(SwapParams memory params)
        public
        view
    {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: liquidity1 exceeds liquidity0 by more than the rounding.
        givenValidBalancesBeyondMargin(params, false);

        // When: Calling _getQuadraticCoefficients().
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(params);

        // Then: The constant coefficient is negative.
        assertLt(constantCoefficient, 0);

        // And: The linear coefficient is positive.
        assertGt(linearCoefficient, 0);

        // And: The coefficients are within their error bounds of the exact values.
        assertQuadraticCoefficients(params, quadraticCoefficient, linearCoefficient, constantCoefficient);
    }
}
