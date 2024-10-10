/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery-fork/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceLogic_Fuzz_Test } from "./_RebalanceLogic.fuzz.t.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalanceLogic } from "../../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";

/**
 * @notice Fuzz tests for the function "_getAmountIn" of contract "RebalanceLogic".
 */
contract GetAmountIn_RebalanceLogic_Fuzz_Test is RebalanceLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalanceLogic_Fuzz_Test) {
        RebalanceLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmountIn_OverflowPriceX96(
        uint256 sqrtPriceX96,
        bool zeroToOne,
        uint256 amountOut,
        uint256 fee
    ) public {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        rebalanceLogic.getAmountIn(sqrtPriceX96, zeroToOne, amountOut, fee);
    }

    function testFuzz_Revert_getAmountIn_ZeroToOne_OverflowFullMath(
        uint256 sqrtPriceX96,
        uint256 amountOut,
        uint256 fee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max
        sqrtPriceX96 = bound(sqrtPriceX96, 0, FixedPoint96.Q96 - 1);

        // And: amountOut is too small.
        amountOut = bound(
            amountOut,
            FullMath.mulDivRoundingUp(type(uint256).max, sqrtPriceX96 ** 2, RebalanceLogic.Q192) + 1,
            type(uint256).max
        );

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        rebalanceLogic.getAmountIn(sqrtPriceX96, true, amountOut, fee);
    }

    function testFuzz_Revert_getAmountIn_OneToZero_OverflowFullMath(
        uint256 sqrtPriceX96,
        uint256 amountOut,
        uint256 fee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than Q96.
        sqrtPriceX96 = bound(sqrtPriceX96, FixedPoint96.Q96 + 1, type(uint128).max);

        // And: amountOut is too big.
        amountOut = bound(
            amountOut,
            FullMath.mulDivRoundingUp(type(uint256).max, RebalanceLogic.Q192, sqrtPriceX96 ** 2) + 1,
            type(uint256).max
        );

        // When: Calling _getAmountIn().
        // Then: It should revert.
        vm.expectRevert(bytes(""));
        rebalanceLogic.getAmountIn(sqrtPriceX96, false, amountOut, fee);
    }

    function testFuzz_Success_getAmountIn_ZeroToOne(uint256 sqrtPriceX96, uint256 amountOut, uint256 fee) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than 0.
        sqrtPriceX96 = bound(sqrtPriceX96, 1, type(uint128).max);

        // And: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: amountOut is not too big.
        if (sqrtPriceX96 < FixedPoint96.Q96 * 1e9) {
            amountOut =
                bound(amountOut, 0, FullMath.mulDiv(type(uint256).max / 1e18, sqrtPriceX96 ** 2, RebalanceLogic.Q192));
        }

        // When: Calling _getAmountIn().
        uint256 amountIn = rebalanceLogic.getAmountIn(sqrtPriceX96, true, amountOut, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = FullMath.mulDiv(amountOut, RebalanceLogic.Q192, sqrtPriceX96 ** 2);
        uint256 amountInExpected = amountInWithoutFees * 1e18 / (1e18 - fee);
        assertEq(amountIn, amountInExpected);
    }

    function testFuzz_Success_getAmountIn_OneToZero(uint256 sqrtPriceX96, uint256 amountOut, uint256 fee) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max, but bigger than Q96.
        sqrtPriceX96 = bound(sqrtPriceX96, 0, type(uint128).max);

        // And: fee is smaller than 100%.
        fee = bound(fee, 0, 1e18 - 1);

        // And: amountOut is not too big.
        if (sqrtPriceX96 * 1e9 > FixedPoint96.Q96) {
            amountOut =
                bound(amountOut, 0, FullMath.mulDiv(type(uint256).max / 1e18, RebalanceLogic.Q192, sqrtPriceX96 ** 2));
        }

        // When: Calling _getAmountIn().
        uint256 amountIn = rebalanceLogic.getAmountIn(sqrtPriceX96, false, amountOut, fee);

        // Then: It should return the correct value.
        uint256 amountInWithoutFees = FullMath.mulDiv(amountOut, sqrtPriceX96 ** 2, RebalanceLogic.Q192);
        uint256 amountInExpected = amountInWithoutFees * 1e18 / (1e18 - fee);
        assertEq(amountIn, amountInExpected);
    }
}
