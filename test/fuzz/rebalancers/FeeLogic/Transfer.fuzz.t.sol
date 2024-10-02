/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FeeLogic_Fuzz_Test } from "./_FeeLogic.fuzz.t.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";

/**
 * @notice Fuzz tests for the function "_transfer" of contract "FeeLogic".
 */
contract Transfer_FeeLogic_Fuzz_Test is FeeLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(FeeLogic_Fuzz_Test) {
        FeeLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_transfer_ZeroToOne(
        address initiator,
        uint256 amountInitiatorFee,
        uint256 balance0,
        uint256 balance1
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(feeLogic));

        // And: The two tokens.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        deal(address(token0), address(feeLogic), amountInitiatorFee, true);

        // When: Calling _transfer().
        (uint256 balanceNew0, uint256 balanceNew1) =
            feeLogic.transfer(initiator, true, amountInitiatorFee, address(token0), address(token1), balance0, balance1);

        // Then: It should return the correct values.
        assertEq(balanceNew0, balance0 > amountInitiatorFee ? balance0 - amountInitiatorFee : 0);
        assertEq(balanceNew1, balance1);

        // And: The initiator should have received the amount of token0 as reward.
        assertEq(token0.balanceOf(initiator), balance0 > amountInitiatorFee ? amountInitiatorFee : balance0);
    }

    function testFuzz_Success_transfer_OneToZero(
        address initiator,
        uint256 amountInitiatorFee,
        uint256 balance0,
        uint256 balance1
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(feeLogic));

        // And: The two tokens.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        deal(address(token1), address(feeLogic), amountInitiatorFee, true);

        // When: Calling _transfer().
        (uint256 balanceNew0, uint256 balanceNew1) =
            feeLogic.transfer(initiator, false, amountInitiatorFee, address(token0), address(token1), balance0, balance1);

        // Then: It should return the correct values.
        assertEq(balanceNew0, balance0);
        assertEq(balanceNew1, balance1 > amountInitiatorFee ? balance1 - amountInitiatorFee : 0);

        // And: The initiator should have received the amount of token0 as reward.
        assertEq(token1.balanceOf(initiator), balance1 > amountInitiatorFee ? amountInitiatorFee : balance1);
    }
}
