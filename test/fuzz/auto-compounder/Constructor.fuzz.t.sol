/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder_Fuzz_Test, AutoCompounderExtension, AutoCompounder } from "./_AutoCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "AutoCompounder".
 */
contract Constructor_AutoCompounder_Fuzz_Test is AutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        AutoCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_Constructor_MaxTolerance() public {
        vm.startPrank(users.creatorAddress);
        vm.expectRevert(AutoCompounder.MaxToleranceExceeded.selector);
        autoCompounder = new AutoCompounderExtension(5001, MIN_USD_FEES_VALUE, INITIATOR_FEE);
    }

    function testFuzz_Revert_Constructor_MaxInitiatorFee() public {
        vm.startPrank(users.creatorAddress);
        vm.expectRevert(AutoCompounder.MaxInitiatorFeeExceeded.selector);
        autoCompounder = new AutoCompounderExtension(TOLERANCE, MIN_USD_FEES_VALUE, 2001);
    }

    function testFuzz_Success_Constructor() public {
        vm.prank(users.creatorAddress);
        autoCompounder = new AutoCompounderExtension(TOLERANCE, MIN_USD_FEES_VALUE, INITIATOR_FEE);

        assertEq(address(autoCompounder.UNI_V3_FACTORY()), 0x33128a8fC17869897dcE68Ed026d694621f6FDfD);
        assertEq(address(autoCompounder.REGISTRY()), 0xd0690557600eb8Be8391D1d97346e2aab5300d5f);
        assertEq(address(autoCompounder.NONFUNGIBLE_POSITION_MANAGER()), 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
        // Sqrt of (BIPS + 1000) * BIPS is 10488
        assertEq(autoCompounder.MAX_UPPER_SQRT_PRICE_DEVIATION(), 10_198);
        assertEq(autoCompounder.MAX_LOWER_SQRT_PRICE_DEVIATION(), 9797);
        assertEq(autoCompounder.TOLERANCE(), TOLERANCE);
        assertEq(autoCompounder.MIN_USD_FEES_VALUE(), MIN_USD_FEES_VALUE);
        assertEq(autoCompounder.INITIATOR_FEE(), INITIATOR_FEE);
    }
}
