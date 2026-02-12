/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";

/**
 * @notice Fuzz tests for the function "_repayDebt" of contract "Closer".
 */
contract RepayDebt_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    LendingPoolMock public lendingPoolMock;

    function setUp() public override {
        Closer_Fuzz_Test.setUp();

        // Add token1 to Arcadia (required for numeraire).
        addAssetToArcadia(address(token1), int256(1e18));

        // Deploy mock lending pool.
        lendingPoolMock = new LendingPoolMock(address(token1));

        // Open margin account with lendingPoolMock as creditor.
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_repayDebt_NoRepayment(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        uint256 debt
    ) public {
        // Given: maxRepayAmount is zero.
        uint256 maxRepayAmount = 0;

        // And: Valid balances and fees.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = bound(fee0, 0, balance0);
        fees[1] = bound(fee1, 0, balance1);

        // And: Account can have debt.
        lendingPoolMock.setDebt(address(account), debt);

        // When: Calling _repayDebt with maxRepayAmount = 0.
        vm.prank(address(account));
        uint256[] memory balances_ = closer.repayDebt(balances, fees, address(token1), 1, maxRepayAmount);

        // Then: Balances should remain unchanged.
        assertEq(balances_[0], balances[0]);
        assertEq(balances_[1], balances[1]);

        // And: Debt remains unchanged.
        assertEq(lendingPoolMock.debt(address(account)), debt);
    }

    function testFuzz_Success_repayDebt_RepayLimitedByDebt(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        uint256 debt,
        uint256 maxRepayAmount
    ) public {
        // Given: Account can have debt.
        lendingPoolMock.setDebt(address(account), debt);

        // And: Available balance is greater or equal to debt.
        balance1 = bound(balance1, debt, type(uint256).max);
        fee1 = bound(fee1, 0, balance1 - debt);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = bound(fee0, 0, balance0);
        fees[1] = fee1;
        deal(address(token1), address(closer), balance1, true);

        // And: maxRepayAmount is greater or equal to debt.
        maxRepayAmount = bound(maxRepayAmount, debt, type(uint256).max);

        // When: Calling _repayDebt.
        vm.prank(address(account));
        balances = closer.repayDebt(balances, fees, address(token1), 1, maxRepayAmount);

        // Then: Balance for token0 should remain unchanged.
        assertEq(balances[0], balance0);

        // And: Balance for token1 should be reduced by the debt amount.
        assertEq(balances[1], balance1 - debt);

        // And: Debt should be fully repaid.
        assertEq(lendingPoolMock.debt(address(account)), 0);
    }

    function testFuzz_Success_repayDebt_RepayLimitedByBalance(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        uint256 debt,
        uint256 maxRepayAmount
    ) public {
        // Given: Valid balances and fees.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = bound(fee0, 0, balance0);
        fees[1] = bound(fee1, 0, balance1);
        deal(address(token1), address(closer), balance1, true);
        uint256 availableBalance = balance1 - fees[1];

        // And: Debt is greater or equal to available balance.
        debt = bound(debt, availableBalance, type(uint256).max);
        lendingPoolMock.setDebt(address(account), debt);

        // And: maxRepayAmount is greater or equal to available balance.
        maxRepayAmount = bound(maxRepayAmount, debt, type(uint256).max);

        // When: Calling _repayDebt.
        vm.prank(address(account));
        balances = closer.repayDebt(balances, fees, address(token1), 1, maxRepayAmount);

        // Then: Balance for token0 should remain unchanged.
        assertEq(balances[0], balance0);

        // And: Balance for token1 should be reduced by the available balance.
        assertEq(balances[1], balance1 - availableBalance);

        // And: Debt should be reduced by the available balance.
        assertEq(lendingPoolMock.debt(address(account)), debt - availableBalance);
    }

    function testFuzz_Success_repayDebt_RepayLimitedByMaxRepayAmount(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        uint256 debt,
        uint256 maxRepayAmount
    ) public {
        // Given: Available balance is greater or equal to maxRepayAmount.
        balance1 = bound(balance1, maxRepayAmount, type(uint256).max);
        fee1 = bound(fee1, 0, balance1 - maxRepayAmount);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = bound(fee0, 0, balance0);
        fees[1] = fee1;
        deal(address(token1), address(closer), balance1, true);

        // And: Debt is greater or equal to maxRepayAmount
        debt = bound(debt, maxRepayAmount, type(uint256).max);
        lendingPoolMock.setDebt(address(account), debt);

        // When: Calling _repayDebt.
        vm.prank(address(account));
        balances = closer.repayDebt(balances, fees, address(token1), 1, maxRepayAmount);

        // Then: Balance for token0 should remain unchanged.
        assertEq(balances[0], balance0);

        // And: Balance for token1 should be reduced by maxRepayAmount.
        assertEq(balances[1], balance1 - maxRepayAmount);

        // And: Debt should be reduced by maxRepayAmount.
        assertEq(lendingPoolMock.debt(address(account)), debt - maxRepayAmount);
    }
}
