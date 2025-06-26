/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AbstractBase } from "../../../../../src/cl-managers/base/AbstractBase.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";
import { UniswapV3Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";

/**
 * @notice Fuzz tests for the function "_approveAndTransfer" of contract "YieldClaimer".
 */
contract ApproveAndTransfer_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(YieldClaimer_Fuzz_Test) {
        YieldClaimer_Fuzz_Test.setUp();

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_approveAndTransfer_AccountIsRecipient_AllZero(
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator,
        address account_
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: Fees are bigger or equal than balances.
        fee0 = bound(fee0, 0, type(uint256).max);
        fee1 = bound(fee1, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);
        balance1 = bound(balance1, 0, fee1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, account_
            );

            // Then: It should return the correct count.
            assertEq(count, 1);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(yieldClaimer), account_), 0);
        assertEq(token1.allowance(address(yieldClaimer), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsRecipient_Token1Zero(
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator,
        address account_
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: balance0 is bigger than fee0.
        balance0 = bound(balance0, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);

        // And: Fee1 is bigger or equal than balance1.
        fee1 = bound(fee1, 0, type(uint256).max);
        balance1 = bound(balance1, 0, fee1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        {
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, account_
            );

            // Then: It should return the correct count.
            assertEq(count, 2);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(yieldClaimer), account_), balances[0]);
        assertEq(token1.allowance(address(yieldClaimer), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsRecipient_Token0Zero(
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator,
        address account_
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: Fee0 is bigger or equal than balance0.
        fee0 = bound(fee0, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);

        // And: balance1 is bigger than fee1.
        balance1 = bound(balance1, 1, type(uint256).max);
        fee1 = bound(fee1, 0, balance1 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, account_
            );

            // Then: It should return the correct count.
            assertEq(count, 2);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(yieldClaimer), account_), 0);
        assertEq(token1.allowance(address(yieldClaimer), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), fee1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsRecipient_AllNonZero(
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator,
        address account_
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: Balances are bigger than fees.
        balance0 = bound(balance0, 1, type(uint256).max);
        balance1 = bound(balance1, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);
        fee1 = bound(fee1, 0, balance1 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, account_
            );

            // Then: It should return the correct count.
            assertEq(count, 3);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(yieldClaimer), account_), balances[0]);
        assertEq(token1.allowance(address(yieldClaimer), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), fee1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsNotRecipient_AllZero(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        PositionState memory position,
        address initiator,
        address account_,
        address recipient
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != account_);
        vm.assume(recipient != address(0));

        // And: Fees are bigger or equal than balances.
        fee0 = bound(fee0, 0, type(uint256).max);
        fee1 = bound(fee1, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);
        balance1 = bound(balance1, 0, fee1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token0), 0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token1), 0);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, recipient
            );

            // Then: It should return the correct count.
            assertEq(count, 1);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are transferred.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.balanceOf(recipient), 0);
        assertEq(token1.balanceOf(recipient), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsNotRecipient_Token1Zero(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        PositionState memory position,
        address initiator,
        address account_,
        address recipient
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != account_);
        vm.assume(recipient != address(0));

        // And: balance0 is bigger than fee0.
        balance0 = bound(balance0, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);

        // And: Fee1 is bigger or equal than balance1.
        fee1 = bound(fee1, 0, type(uint256).max);
        balance1 = bound(balance1, 0, fee1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit YieldClaimer.YieldTransferred(account_, recipient, address(token0), balance0 - fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.expectEmit();
        emit YieldClaimer.YieldTransferred(account_, recipient, address(token1), 0);
        vm.prank(account_);
        {
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, recipient
            );

            // Then: It should return the correct count.
            assertEq(count, 1);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.balanceOf(recipient), balance0 - fee0);
        assertEq(token1.balanceOf(recipient), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsNotRecipient_Token0Zero(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        PositionState memory position,
        address initiator,
        address account_,
        address recipient
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != account_);
        vm.assume(recipient != address(0));

        // And: Fee0 is bigger or equal than balance0.
        fee0 = bound(fee0, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);

        // And: balance1 is bigger than fee1.
        balance1 = bound(balance1, 1, type(uint256).max);
        fee1 = bound(fee1, 0, balance1 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token0), 0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token1), balance1 - fee1);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, recipient
            );

            // Then: It should return the correct count.
            assertEq(count, 1);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.balanceOf(recipient), 0);
        assertEq(token1.balanceOf(recipient), balance1 - fee1);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), fee1);
    }

    function testFuzz_Success_approveAndTransfer_AccountIsNotRecipient_AllNonZero(
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        PositionState memory position,
        address initiator,
        address account_,
        address recipient
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(yieldClaimer));

        // And: account is not the Yield claimer.
        vm.assume(account_ != address(yieldClaimer));

        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != account_);
        vm.assume(recipient != address(0));

        // And: Balances are bigger than fees.
        balance0 = bound(balance0, 1, type(uint256).max);
        balance1 = bound(balance1, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);
        fee1 = bound(fee1, 0, balance1 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(yieldClaimer), balance0, true);
        deal(address(token1), address(yieldClaimer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(yieldClaimer), position.id);

        // When: Calling _approveAndTransfer().
        {
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token0), balance0 - fee0);
            vm.expectEmit();
            emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
            vm.expectEmit();
            emit YieldClaimer.YieldTransferred(account_, recipient, address(token1), balance1 - fee1);
            vm.prank(account_);
            uint256 count;
            (balances, count) = yieldClaimer.approveAndTransfer(
                initiator, balances, fees, address(nonfungiblePositionManager), position, recipient
            );

            // Then: It should return the correct count.
            assertEq(count, 1);
        }

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), account_);

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.balanceOf(recipient), balance0 - fee0);
        assertEq(token1.balanceOf(recipient), balance1 - fee1);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), fee1);
    }
}
