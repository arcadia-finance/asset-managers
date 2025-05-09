/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_transferInitiatorFee" of contract "Rebalancer".
 */
contract TransferInitiatorFee_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(Rebalancer_Fuzz_Test) {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_transfer_ZeroToOne(
        address initiator,
        uint256 amountInitiatorFee,
        uint256 balance0,
        uint256 balance1,
        Rebalancer.PositionState memory position
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: rebalancer has balance.
        deal(address(token0), address(rebalancer), amountInitiatorFee, true);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // When: Calling _transfer().
        balances = rebalancer.transferInitiatorFee(balances, position, true, amountInitiatorFee, initiator);

        // Then: It should return the correct values.
        assertEq(balances[0], balance0 > amountInitiatorFee ? balance0 - amountInitiatorFee : 0);
        assertEq(balances[1], balance1);

        // And: The initiator should have received the amount of token0 as reward.
        assertEq(token0.balanceOf(initiator), balance0 > amountInitiatorFee ? amountInitiatorFee : balance0);
    }

    function testFuzz_Success_transfer_OneToZero(
        address initiator,
        uint256 amountInitiatorFee,
        uint256 balance0,
        uint256 balance1,
        Rebalancer.PositionState memory position
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: rebalancer has balance.
        deal(address(token1), address(rebalancer), amountInitiatorFee, true);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // When: Calling _transfer().
        balances = rebalancer.transferInitiatorFee(balances, position, false, amountInitiatorFee, initiator);

        // Then: It should return the correct values.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1 > amountInitiatorFee ? balance1 - amountInitiatorFee : 0);

        // And: The initiator should have received the amount of token0 as reward.
        assertEq(token1.balanceOf(initiator), balance1 > amountInitiatorFee ? amountInitiatorFee : balance1);
    }
}
