/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorInfo" of contract "Rebalancer".
 */
contract SetInitiatorInfo_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidFee(
        address initiator,
        uint256 tolerance,
        uint256 swapFee,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = rebalancer.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: upperSqrtPriceDeviation does not overflow.
        tolerance = bound(tolerance, 0, type(uint88).max);

        // And: swapFee is > Max Initiator Fee
        swapFee = bound(swapFee, rebalancer.MAX_INITIATOR_FEE() + 1, type(uint256).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setInitiatorInfo(tolerance, swapFee, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidTolerance(
        address initiator,
        uint256 tolerance,
        uint256 swapFee,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = rebalancer.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, rebalancer.MAX_INITIATOR_FEE());

        // Given : Tolerance is > maximum tolerance.
        tolerance = bound(tolerance, rebalancer.MAX_TOLERANCE() + 1, type(uint88).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setInitiatorInfo(tolerance, swapFee, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidMinLiquidityRatio_TooBig(
        address initiator,
        uint256 tolerance,
        uint256 swapFee,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = rebalancer.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, rebalancer.MAX_INITIATOR_FEE());

        // And: Tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, rebalancer.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is > 1e18.
        minLiquidityRatio = bound(minLiquidityRatio, 1e18 + 1, type(uint88).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setInitiatorInfo(tolerance, swapFee, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidMinLiquidityRatio_TooSmall(
        address initiator,
        uint256 tolerance,
        uint256 swapFee,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = rebalancer.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, rebalancer.MAX_INITIATOR_FEE());

        // And: Tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, rebalancer.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is < minimum liquidity ratio.
        minLiquidityRatio = bound(minLiquidityRatio, 0, rebalancer.MIN_LIQUIDITY_RATIO() - 1);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setInitiatorInfo(tolerance, swapFee, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidFee(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 initMinLiquidityRatio,
        uint256 newTolerance,
        uint256 newFee,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee, initMinLiquidityRatio);

        // And: New upperSqrtPriceDeviation does not overflow.
        newTolerance = bound(newTolerance, 0, type(uint88).max);

        // And: New Fee is > initial swapFee.
        newFee = bound(newFee, initFee + 1, type(uint256).max);

        // When: Initiator updates the swapFee to a higher value.
        // Then: It should revert.
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidTolerance(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 initMinLiquidityRatio,
        uint256 newTolerance,
        uint256 newFee,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is > initial tolerance.
        newTolerance = bound(newTolerance, initTolerance + 1, type(uint88).max);
        uint256 initSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + initTolerance) * 1e18);
        uint256 newUpperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        vm.assume(newUpperSqrtPriceDeviation > initSqrtPriceDeviation);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidMinLiquidityRatio_TooBig(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 initMinLiquidityRatio,
        uint256 newTolerance,
        uint256 newFee,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New newMinLiquidityRatio > 1e18.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, 1e18 + 1, type(uint88).max);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidMinLiquidityRatio_TooSmall(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 initMinLiquidityRatio,
        uint256 newTolerance,
        uint256 newFee,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New newMinLiquidityRatio <  initial minLiquidityRatio.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, 0, initMinLiquidityRatio - 1);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee, newMinLiquidityRatio);
    }

    function testFuzz_Success_setInitiatorInfo_NotInitialised(
        address initiator,
        uint256 tolerance,
        uint256 swapFee,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = rebalancer.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, rebalancer.MAX_INITIATOR_FEE());

        // And: tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, rebalancer.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is within boundaries.
        minLiquidityRatio = bound(minLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, swapFee, minLiquidityRatio);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        (
            uint256 upperSqrtPriceDeviation,
            uint256 lowerSqrtPriceDeviation,
            uint256 swapFee_,
            ,
            uint256 minLiquidityRatio_
        ) = rebalancer.initiatorInfo(initiator);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(swapFee, swapFee_);
        assertEq(minLiquidityRatio, minLiquidityRatio_);
    }

    function testFuzz_Success_setInitiatorInfo_Initialised(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 initMinLiquidityRatio,
        uint256 newTolerance,
        uint256 newFee,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, rebalancer.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New Min Liquidity Ratio is within boundaries.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, initMinLiquidityRatio, 1e18);

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee, newMinLiquidityRatio);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - newTolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation, uint256 swapFee,, uint256 minLiquidityRatio_)
        = rebalancer.initiatorInfo(initiator);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(newFee, swapFee);
        assertEq(newMinLiquidityRatio, minLiquidityRatio_);
    }
}
