/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

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
    function testFuzz_Revert_setInitiatorInfo_Reentered(
        address initiator,
        address account_,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: A rebalance is ongoing.
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.setInitiatorInfo(tolerance, fee);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_MaxInitiatorFee(
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Initiator is not initialised.
        (,,, bool initialized) = rebalancer.initiatorInfo(initiator);
        vm.assume(!initialized);

        // And: upperSqrtPriceDeviation does not overflow.
        tolerance = bound(tolerance, 0, type(uint88).max);

        // And: fee is > Max Initiator Fee
        fee = bound(fee, rebalancer.MAX_INITIATOR_FEE() + 1, type(uint256).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.MaxInitiatorFee.selector);
        rebalancer.setInitiatorInfo(tolerance, fee);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_MaxTolerance(
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Initiator is not initialised.
        (,,, bool initialized) = rebalancer.initiatorInfo(initiator);
        vm.assume(!initialized);

        // And: fee is < Max Initiator Fee.
        fee = bound(fee, 0, rebalancer.MAX_INITIATOR_FEE());

        // Given : Tolerance is > maximum tolerance.
        tolerance = bound(tolerance, rebalancer.MAX_TOLERANCE() + 1, type(uint88).max);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.MaxTolerance.selector);
        rebalancer.setInitiatorInfo(tolerance, fee);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_DecreaseFeeOnly(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 newTolerance,
        uint256 newFee
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee);

        // And: New upperSqrtPriceDeviation does not overflow.
        newTolerance = bound(newTolerance, 0, type(uint88).max);

        // And: New Fee is > initial fee.
        newFee = bound(newFee, initFee + 1, type(uint256).max);

        // When: Initiator updates the fee to a higher value.
        // Then: It should revert.
        vm.expectRevert(Rebalancer.DecreaseFeeOnly.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_DecreaseToleranceOnly(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 newTolerance,
        uint256 newFee
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee);

        // And: New Fee is < initial fee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is > initial tolerance.
        newTolerance = bound(newTolerance, initTolerance + 1, type(uint88).max);
        uint256 initSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + initTolerance) * 1e18);
        uint256 newUpperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        vm.assume(newUpperSqrtPriceDeviation > initSqrtPriceDeviation);

        // When : Initiator updates the fee to a higher value
        // Then : It should revert
        vm.expectRevert(Rebalancer.DecreaseToleranceOnly.selector);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, 0);
    }

    function testFuzz_Success_setInitiatorInfo_NotInitialised(address initiator, uint256 tolerance, uint256 fee)
        public
    {
        // Given: Initiator is not initialised.
        (,,, bool initialized) = rebalancer.initiatorInfo(initiator);
        vm.assume(!initialized);

        // And: fee is < Max Initiator Fee.
        fee = bound(fee, 0, rebalancer.MAX_INITIATOR_FEE());

        // And: tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, rebalancer.MAX_TOLERANCE());

        // When: Initiator sets a tolerance and fee.
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation, uint256 fee_, bool initialized_) =
            rebalancer.initiatorInfo(initiator);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(fee, fee_);
        assertTrue(initialized_);
    }

    function testFuzz_Success_setInitiatorInfo_Initialised(
        address initiator,
        uint256 initTolerance,
        uint256 initFee,
        uint256 newTolerance,
        uint256 newFee
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, rebalancer.MAX_INITIATOR_FEE());
        initTolerance = bound(initTolerance, 0, rebalancer.MAX_TOLERANCE());
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, initFee);

        // And: New Fee is < initial fee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // When: Initiator sets a tolerance and fee.
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(newTolerance, newFee);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - newTolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation, uint256 fee, bool initialized) =
            rebalancer.initiatorInfo(initiator);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(newFee, fee);
        assertTrue(initialized);
    }
}
