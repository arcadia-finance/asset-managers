/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorInfo" of contract "UniswapV3Rebalancer".
 */
contract SetInitiatorInfo_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setInitiatorInfo_DecreaseFeeOnly(address initiator, uint256 initFee, uint256 newFee)
        public
    {
        // Given : New fee is > initial fee
        initFee = bound(initFee, 1, rebalancer.MAX_INITIATOR_FEE() - 1);
        newFee = bound(newFee, initFee + 1, rebalancer.MAX_INITIATOR_FEE());

        // And : Initial info is already set for initiator
        vm.startPrank(initiator);
        rebalancer.setInitiatorInfo(0, initFee);

        // When : Initiator updates the fee to a higher value
        // Then : It should revert
        vm.expectRevert(UniswapV3Rebalancer.DecreaseFeeOnly.selector);
        rebalancer.setInitiatorInfo(0, newFee);
    }

    function testFuzz_Revert_setInitiatorInfo_MaxInitiatorFee(address initiator, uint256 fee) public {
        // Given : fee is > Max Initiator Fee
        fee = bound(fee, rebalancer.MAX_INITIATOR_FEE() + 1, type(uint256).max);

        vm.startPrank(initiator);
        // When : Initiator sets a fee higher than the max
        // Then : It should revert
        vm.expectRevert(UniswapV3Rebalancer.MaxInitiatorFee.selector);
        rebalancer.setInitiatorInfo(0, fee);
    }

    function testFuzz_Revert_setInitiatorInfo_MaxTolerance(address initiator, uint256 tolerance) public {
        // Given : Tolerance is > maximum tolerance
        tolerance = bound(tolerance, rebalancer.MAX_TOLERANCE() + 1, type(uint256).max);

        vm.startPrank(initiator);
        // When : Initiator sets a tolerance higher than the max
        // Then : It should revert
        vm.expectRevert(UniswapV3Rebalancer.MaxTolerance.selector);
        rebalancer.setInitiatorInfo(tolerance, 0);
    }

    function testFuzz_Revert_setInitiatorInfo_DecreaseToleranceOnly(
        address initiator,
        uint256 initTolerance,
        uint256 newTolerance
    ) public {
        // Given : New fee is > initial fee
        initTolerance = bound(initTolerance, 1, rebalancer.MAX_TOLERANCE() - 1);
        newTolerance = bound(newTolerance, initTolerance + 1, rebalancer.MAX_TOLERANCE());

        uint256 initSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + initTolerance) * 1e18);
        uint256 newUpperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        vm.assume(newUpperSqrtPriceDeviation > initSqrtPriceDeviation);

        // And : Initial info is already set for initiator
        vm.startPrank(initiator);
        rebalancer.setInitiatorInfo(initTolerance, 0);

        // When : Initiator updates the fee to a higher value
        // Then : It should revert
        vm.expectRevert(UniswapV3Rebalancer.DecreaseToleranceOnly.selector);
        rebalancer.setInitiatorInfo(newTolerance, 0);
    }

    function testFuzz_Success_setInitiatorInfo(address initiator, uint256 tolerance, uint256 fee) public {
        // Given : Tolerance and fee are within limits
        tolerance = bound(tolerance, 1, rebalancer.MAX_TOLERANCE());
        fee = bound(fee, 1, rebalancer.MAX_INITIATOR_FEE());

        // When : Initiator sets a tolerance and fee
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // Then : Values should be set and correct
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation, uint256 fee_) =
            rebalancer.initiatorInfo(initiator);
        assertEq(upperSqrtPriceDeviation_, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation_, lowerSqrtPriceDeviation_);
        assertEq(fee, fee_);
    }
}
