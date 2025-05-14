/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Compounder } from "../../../../src/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorInfo" of contract "Compounder".
 */
contract SetInitiatorInfo_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiatorInfo_Reentered(
        address initiator,
        address account_,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidClaimFee(
        address initiator,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: upperSqrtPriceDeviation does not overflow.
        tolerance = bound(tolerance, 0, type(uint88).max);

        // And: claimFee is > Max Initiator Fee
        claimFee = bound(claimFee, compounder.MAX_FEE() + 1, type(uint256).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidSwapFee(
        address initiator,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: upperSqrtPriceDeviation does not overflow.
        tolerance = bound(tolerance, 0, type(uint88).max);

        // And: swapFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, compounder.MAX_FEE());

        // And: swapFee is > Max Initiator Fee
        swapFee = bound(swapFee, compounder.MAX_FEE() + 1, type(uint256).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidTolerance(
        address initiator,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, compounder.MAX_FEE());

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, compounder.MAX_FEE());

        // Given : Tolerance is > maximum tolerance.
        tolerance = bound(tolerance, compounder.MAX_TOLERANCE() + 1, type(uint88).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidMinLiquidityRatio_TooBig(
        address initiator,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, compounder.MAX_FEE());

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, compounder.MAX_FEE());

        // And: Tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, compounder.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is > 1e18.
        minLiquidityRatio = bound(minLiquidityRatio, 1e18 + 1, type(uint88).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidMinLiquidityRatio_TooSmall(
        address initiator,
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, compounder.MAX_FEE());

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, compounder.MAX_FEE());

        // And: Tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, compounder.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is < minimum liquidity ratio.
        minLiquidityRatio = bound(minLiquidityRatio, 0, compounder.MIN_LIQUIDITY_RATIO() - 1);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidFee(
        address initiator,
        uint256 initFee,
        uint256 initTolerance,
        uint256 initMinLiquidityRatio,
        uint256 newFee,
        uint256 newTolerance,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_FEE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        compounder.setInitiatorInfo(initFee, initFee, initTolerance, initMinLiquidityRatio);

        // And: New upperSqrtPriceDeviation does not overflow.
        newTolerance = bound(newTolerance, 0, type(uint88).max);

        // And: New Fee is > initial swapFee.
        newFee = bound(newFee, initFee + 1, type(uint256).max);

        // When: Initiator updates the swapFee to a higher value.
        // Then: It should revert.
        vm.expectRevert(Compounder.InvalidValue.selector);
        vm.prank(initiator);
        compounder.setInitiatorInfo(newFee, newFee, newTolerance, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidTolerance(
        address initiator,
        uint256 initFee,
        uint256 initTolerance,
        uint256 initMinLiquidityRatio,
        uint256 newFee,
        uint256 newTolerance,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_FEE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        compounder.setInitiatorInfo(initFee, initFee, initTolerance, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is > initial tolerance.
        newTolerance = bound(newTolerance, initTolerance + 1, type(uint88).max);
        uint256 initSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + initTolerance) * 1e18);
        uint256 newUpperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        vm.assume(newUpperSqrtPriceDeviation > initSqrtPriceDeviation);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Compounder.InvalidValue.selector);
        vm.prank(initiator);
        compounder.setInitiatorInfo(newFee, newFee, newTolerance, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidMinLiquidityRatio_TooBig(
        address initiator,
        uint256 initFee,
        uint256 initTolerance,
        uint256 initMinLiquidityRatio,
        uint256 newFee,
        uint256 newTolerance,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_FEE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        compounder.setInitiatorInfo(initFee, initFee, initTolerance, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New newMinLiquidityRatio > 1e18.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, 1e18 + 1, type(uint88).max);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Compounder.InvalidValue.selector);
        vm.prank(initiator);
        compounder.setInitiatorInfo(newFee, newFee, newTolerance, newMinLiquidityRatio);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidMinLiquidityRatio_TooSmall(
        address initiator,
        uint256 initFee,
        uint256 initTolerance,
        uint256 initMinLiquidityRatio,
        uint256 newFee,
        uint256 newTolerance,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_FEE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        compounder.setInitiatorInfo(initFee, initFee, initTolerance, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New newMinLiquidityRatio <  initial minLiquidityRatio.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, 0, initMinLiquidityRatio - 1);

        // When : Initiator updates the swapFee to a higher value
        // Then : It should revert
        vm.expectRevert(Compounder.InvalidValue.selector);
        vm.prank(initiator);
        compounder.setInitiatorInfo(newFee, newFee, newTolerance, newMinLiquidityRatio);
    }

    function testFuzz_Success_setInitiatorInfo_NotInitialised(
        uint256 claimFee,
        uint256 swapFee,
        uint256 tolerance,
        address initiator,
        uint256 minLiquidityRatio
    ) public {
        // Given: Initiator is not initialised.
        (,,,, uint256 minLiquidityRatio__) = compounder.initiatorInfo(initiator);
        vm.assume(minLiquidityRatio__ == 0);

        // And: swapFee is < Max Initiator Fee.
        claimFee = bound(claimFee, 0, compounder.MAX_FEE());

        // And: swapFee is < Max Initiator Fee.
        swapFee = bound(swapFee, 0, compounder.MAX_FEE());

        // And: tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, compounder.MAX_TOLERANCE());

        // And: Min Liquidity Ratio is within boundaries.
        minLiquidityRatio = bound(minLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        compounder.setInitiatorInfo(claimFee, swapFee, tolerance, minLiquidityRatio);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        (
            uint256 claimFee_,
            uint256 swapFee_,
            uint256 upperSqrtPriceDeviation,
            uint256 lowerSqrtPriceDeviation,
            uint256 minLiquidityRatio_
        ) = compounder.initiatorInfo(initiator);
        assertEq(claimFee, claimFee_);
        assertEq(swapFee, swapFee_);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(minLiquidityRatio, minLiquidityRatio_);
    }

    function testFuzz_Success_setInitiatorInfo_Initialised(
        address initiator,
        uint256 initFee,
        uint256 initTolerance,
        uint256 initMinLiquidityRatio,
        uint256 newFee,
        uint256 newTolerance,
        uint256 newMinLiquidityRatio
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_FEE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        initMinLiquidityRatio = bound(initMinLiquidityRatio, compounder.MIN_LIQUIDITY_RATIO(), 1e18);
        vm.prank(initiator);
        compounder.setInitiatorInfo(initFee, initFee, initTolerance, initMinLiquidityRatio);

        // And: New Fee is < initial swapFee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // And: New Min Liquidity Ratio is within boundaries.
        newMinLiquidityRatio = bound(newMinLiquidityRatio, initMinLiquidityRatio, 1e18);

        // When: Initiator sets a tolerance and swapFee.
        vm.prank(initiator);
        compounder.setInitiatorInfo(newFee, newFee, newTolerance, newMinLiquidityRatio);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - newTolerance) * 1e18);
        (
            uint256 claimFee,
            uint256 swapFee,
            uint256 upperSqrtPriceDeviation,
            uint256 lowerSqrtPriceDeviation,
            uint256 minLiquidityRatio_
        ) = compounder.initiatorInfo(initiator);
        assertEq(newFee, claimFee);
        assertEq(newFee, swapFee);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(newMinLiquidityRatio, minLiquidityRatio_);
    }
}
