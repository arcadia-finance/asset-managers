/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SwapMath_Fuzz_Test } from "./_SwapMath.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParamsExact" of contract "SwapMath".
 */
contract GetSwapParamsExact_SwapMath_Fuzz_Test is SwapMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SwapMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSwapParamsExact_ZeroToOne(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtPriceNew
    ) public view {
        // Given: Swap is zero to one.
        bool zeroToOne = true;

        // And: fee is smaller than 1e6 (invariant).
        fee = bound(fee, 0, 1e6 - 1);

        // And: sqrtPriceOld is within boundaries.
        sqrtPriceOld = uint160(bound(sqrtPriceOld, TickMath.MIN_SQRT_RATIO, TickMath.MIN_SQRT_RATIO));

        // And: sqrtPriceNew is smaller or equal than sqrtPriceOld (zeroToOne).
        sqrtPriceNew = uint160(bound(sqrtPriceNew, TickMath.MIN_SQRT_RATIO, sqrtPriceOld));

        // When: calling _getSwapParamsExact().
        // Then: it does not revert.
        swapMath.getSwapParamsExact(zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtPriceNew);
    }

    function testFuzz_Success_getSwapParamsExact_OneToZero(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtPriceNew
    ) public view {
        // Given: Swap is one to zero.
        bool zeroToOne = false;

        // And: fee is smaller than 1e6 (invariant).
        fee = bound(fee, 0, 1e6 - 1);

        // And: sqrtPriceOld is within boundaries.
        sqrtPriceOld = uint160(bound(sqrtPriceOld, TickMath.MIN_SQRT_RATIO, TickMath.MIN_SQRT_RATIO));

        // And: sqrtPriceNew is bigger or equal than sqrtPriceOld (oneToZero).
        sqrtPriceNew = uint160(bound(sqrtPriceNew, sqrtPriceOld, TickMath.MIN_SQRT_RATIO));

        // When: calling _getSwapParamsExact().
        // Then: it does not revert.
        swapMath.getSwapParamsExact(zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtPriceNew);
    }
}
