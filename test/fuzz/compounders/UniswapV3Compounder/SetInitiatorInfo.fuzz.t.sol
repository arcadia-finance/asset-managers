/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3Compounder_Fuzz_Test } from "./_UniswapV3Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiator" of contract "UniswapV3Compounder".
 */
contract SetInitiatorInfo_UniswapV3Compounder_Fuzz_Test is UniswapV3Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiatorInfo_Reentered(
        address initiator_,
        address account_,
        uint256 tolerance,
        uint256 initiatorShare
    ) public {
        // Given: A compound is ongoing.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling compound
        // Then: it should revert
        vm.prank(initiator_);
        vm.expectRevert(UniswapV3Compounder.Reentered.selector);
        compounder.setInitiatorInfo(tolerance, initiatorShare);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidInitiatorShare(
        address initiator_,
        uint256 tolerance,
        uint256 initiatorShare
    ) public {
        // Given: Initiator is not initialised.
        (uint256 upperSqrtPriceDeviation,,) = compounder.initiatorInfo(initiator_);
        vm.assume(upperSqrtPriceDeviation == 0);

        // And: upperSqrtPriceDeviation does not overflow.
        tolerance = bound(tolerance, 0, type(uint88).max);

        // And: fee is > Max Initiator Fee
        initiatorShare = bound(initiatorShare, compounder.MAX_INITIATOR_SHARE() + 1, type(uint256).max);

        // When: calling compoundFees.
        // Then: it should revert.
        vm.prank(initiator_);
        vm.expectRevert(UniswapV3Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(tolerance, initiatorShare);
    }

    function testFuzz_Revert_setInitiatorInfo_NotInitialised_InvalidTolerance(
        address initiator_,
        uint256 tolerance,
        uint256 initiatorShare
    ) public {
        // Given: Initiator is not initialised.
        (uint256 upperSqrtPriceDeviation,,) = compounder.initiatorInfo(initiator_);
        vm.assume(upperSqrtPriceDeviation == 0);

        // And: fee is < Max Initiator Fee.
        initiatorShare = bound(initiatorShare, 0, compounder.MAX_INITIATOR_SHARE());

        // Given : Tolerance is > maximum tolerance.
        tolerance = bound(tolerance, compounder.MAX_TOLERANCE() + 1, type(uint88).max);

        // When: calling compoundFees
        // Then: it should revert
        vm.prank(initiator_);
        vm.expectRevert(UniswapV3Compounder.InvalidValue.selector);
        compounder.setInitiatorInfo(tolerance, initiatorShare);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidInitiatorShare(
        address initiator_,
        uint256 initTolerance,
        uint256 initInitiatorShare,
        uint256 newTolerance,
        uint256 newInitiatorShare
    ) public {
        // Given: Initiator is initialised.
        initInitiatorShare = bound(initInitiatorShare, 0, compounder.MAX_INITIATOR_SHARE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        vm.prank(initiator_);
        compounder.setInitiatorInfo(initTolerance, initInitiatorShare);

        // And: New upperSqrtPriceDeviation does not overflow.
        newTolerance = bound(newTolerance, 0, type(uint88).max);

        // And: New Fee is > initial fee.
        newInitiatorShare = bound(newInitiatorShare, initInitiatorShare + 1, type(uint256).max);

        // When: Initiator updates the fee to a higher value.
        // Then: It should revert.
        vm.expectRevert(UniswapV3Compounder.InvalidValue.selector);
        vm.prank(initiator_);
        compounder.setInitiatorInfo(newTolerance, newInitiatorShare);
    }

    function testFuzz_Revert_setInitiatorInfo_Initialised_InvalidTolerance(
        address initiator_,
        uint256 initTolerance,
        uint256 initFee,
        uint256 newTolerance,
        uint256 newFee
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_INITIATOR_SHARE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        vm.prank(initiator_);
        compounder.setInitiatorInfo(initTolerance, initFee);

        // And: New Fee is < initial fee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is > initial tolerance.
        newTolerance = bound(newTolerance, initTolerance + 1, initTolerance + 100_000);
        uint256 initSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + initTolerance) * 1e18);
        uint256 newUpperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        vm.assume(newUpperSqrtPriceDeviation > initSqrtPriceDeviation);

        // When : Initiator updates the fee to a higher value
        // Then : It should revert
        vm.expectRevert(UniswapV3Compounder.InvalidValue.selector);
        vm.prank(initiator_);
        compounder.setInitiatorInfo(newTolerance, newFee);
    }

    function testFuzz_Success_setInitiatorInfo_NotInitialised(address initiator_, uint256 tolerance, uint256 fee)
        public
    {
        // Given: Initiator is not initialised.
        (uint256 upperSqrtPriceDeviation,,) = compounder.initiatorInfo(initiator_);
        vm.assume(upperSqrtPriceDeviation == 0);

        // And: fee is < Max Initiator Fee.
        fee = bound(fee, 0, compounder.MAX_INITIATOR_SHARE());

        // And: tolerance is < maximum tolerance.
        tolerance = bound(tolerance, 0, compounder.MAX_TOLERANCE());

        // When: Initiator sets a tolerance and fee.
        vm.prank(initiator_);
        compounder.setInitiatorInfo(tolerance, fee);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation__, uint256 lowerSqrtPriceDeviation, uint256 fee_) =
            compounder.initiatorInfo(initiator_);
        assertEq(upperSqrtPriceDeviation__, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(fee, fee_);
    }

    function testFuzz_Success_setInitiatorInfo_Initialised(
        address initiator_,
        uint256 initTolerance,
        uint256 initFee,
        uint256 newTolerance,
        uint256 newFee
    ) public {
        // Given: Initiator is initialised.
        initFee = bound(initFee, 0, compounder.MAX_INITIATOR_SHARE());
        initTolerance = bound(initTolerance, 0, compounder.MAX_TOLERANCE());
        vm.prank(initiator_);
        compounder.setInitiatorInfo(initTolerance, initFee);

        // And: New Fee is < initial fee.
        newFee = bound(newFee, 0, initFee);

        // And: New tolerance is < initial tolerance.
        newTolerance = bound(newTolerance, 0, initTolerance);

        // When: Initiator sets a tolerance and fee.
        vm.prank(initiator_);
        compounder.setInitiatorInfo(newTolerance, newFee);

        // Then: Values should be set and correct.
        uint256 upperSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 + newTolerance) * 1e18);
        uint256 lowerSqrtPriceDeviation_ = FixedPointMathLib.sqrt((1e18 - newTolerance) * 1e18);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation, uint256 fee) =
            compounder.initiatorInfo(initiator_);
        assertEq(upperSqrtPriceDeviation, upperSqrtPriceDeviation_);
        assertEq(lowerSqrtPriceDeviation, lowerSqrtPriceDeviation_);
        assertEq(newFee, fee);
    }
}
