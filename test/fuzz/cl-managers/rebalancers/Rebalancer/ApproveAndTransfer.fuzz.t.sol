/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../../../../../src/cl-managers/base/AbstractBase.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { stdError } from "../../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapV3Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";

/**
 * @notice Fuzz tests for the function "_approveAndTransfer" of contract "Rebalancer".
 */
contract ApproveAndTransfer_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(Rebalancer_Fuzz_Test) {
        Rebalancer_Fuzz_Test.setUp();

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_approveAndTransfer_InsufficientBalanceToken0(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: Balance0 are smaller than amountOut0.
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 1, type(uint128).max));
        balance0 = bound(balance0, 0, initiatorParams.amountOut0 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(account_);
        rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );
    }

    function testFuzz_Revert_approveAndTransfer_InsufficientBalanceToken1(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: Balance0 are bigger than amountOut0.
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 0, type(uint128).max));
        balance0 = bound(balance0, initiatorParams.amountOut0, type(uint256).max);
        // And: Balance1 are smaller than amountOut1.
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 1, type(uint128).max));
        balance1 = bound(balance1, 0, initiatorParams.amountOut1 - 1);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(account_);
        rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );
    }

    function testFuzz_Success_approveAndTransfer_NonZeroAmountOuts(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: AmountOuts are non-zero.
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 1, type(uint128).max));
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 1, type(uint128).max));

        // And: Balances are bigger or equal than amountOuts.
        balance0 = bound(balance0, initiatorParams.amountOut0, type(uint256).max);
        balance1 = bound(balance1, initiatorParams.amountOut1, type(uint256).max);

        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 3);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved with at least the amountOut.
        assertGe(balances[0], initiatorParams.amountOut0);
        assertGe(balances[1], initiatorParams.amountOut1);
        assertGe(token0.allowance(address(rebalancer), account_), initiatorParams.amountOut0);
        assertGe(token1.allowance(address(rebalancer), account_), initiatorParams.amountOut1);
    }

    function testFuzz_Success_approveAndTransfer_AllZero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: AmountOuts are zero.
        initiatorParams.amountOut0 = 0;
        initiatorParams.amountOut1 = 0;

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

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 1);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(rebalancer), account_), 0);
        assertEq(token1.allowance(address(rebalancer), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_Token1Zero_WithToken0Leftovers(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: There are leftovers for token0.
        balance0 = bound(balance0, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 0, balance0 - fee0));

        // And: AmountOut1 is zero.
        initiatorParams.amountOut1 = 0;

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

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(rebalancer), account_), balances[0]);
        assertEq(token1.allowance(address(rebalancer), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_Token1Zero_WithoutToken0Leftovers(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: There are no leftovers for token0.
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 1, type(uint128).max));
        balance0 = bound(balance0, initiatorParams.amountOut0, type(uint256).max - 1);
        fee0 = bound(fee0, balance0, type(uint256).max);

        // And: AmountOut1 is zero.
        initiatorParams.amountOut1 = 0;

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

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0 - initiatorParams.amountOut0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], initiatorParams.amountOut0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(rebalancer), account_), balances[0]);
        assertEq(token1.allowance(address(rebalancer), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0 - initiatorParams.amountOut0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_Token0Zero_WithToken1Leftovers(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: AmountOut0 is zero.
        initiatorParams.amountOut0 = 0;

        // And: Fee0 is bigger or equal than balance0.
        fee0 = bound(fee0, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);

        // And: There are leftovers for token1.
        balance1 = bound(balance1, 1, type(uint256).max);
        fee1 = bound(fee1, 0, balance1 - 1);
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 0, balance1 - fee1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: AmountOut0 is zero.
        initiatorParams.amountOut0 = 0;

        // And: AmountOut1 is smaller or equal as balance1.
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 0, balance1));

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(rebalancer), account_), 0);
        assertEq(token1.allowance(address(rebalancer), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), fee1);
    }

    function testFuzz_Success_approveAndTransfer_Token0Zero_WithoutToken1Leftovers(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: AmountOut0 is zero.
        initiatorParams.amountOut0 = 0;

        // And: Fee0 is bigger or equal than balance0.
        fee0 = bound(fee0, 0, type(uint256).max);
        balance0 = bound(balance0, 0, fee0);

        // And: There are no leftovers for token1.
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 1, type(uint128).max));
        balance1 = bound(balance1, initiatorParams.amountOut1, type(uint256).max - 1);
        fee1 = bound(fee1, balance1, type(uint256).max);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: AmountOut0 is zero.
        initiatorParams.amountOut0 = 0;

        // And: AmountOut1 is smaller or equal as balance1.
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 0, balance1));

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1 - initiatorParams.amountOut1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], initiatorParams.amountOut1);
        assertEq(token0.allowance(address(rebalancer), account_), 0);
        assertEq(token1.allowance(address(rebalancer), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), balance1 - initiatorParams.amountOut1);
    }

    function testFuzz_Success_approveAndTransfer_AllNonZero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The account is not the contract.
        vm.assume(account_ != address(rebalancer));

        // And: The initiator is not the contract.
        vm.assume(initiator != address(rebalancer));

        // And: Balances are bigger than fees.
        balance0 = bound(balance0, 1, type(uint256).max);
        balance1 = bound(balance1, 1, type(uint256).max);
        fee0 = bound(fee0, 0, balance0 - 1);
        fee1 = bound(fee1, 0, balance1 - 1);
        initiatorParams.amountOut0 = uint128(bound(initiatorParams.amountOut0, 0, balance0 - fee0));
        initiatorParams.amountOut1 = uint128(bound(initiatorParams.amountOut1, 0, balance1 - fee1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
        vm.prank(account_);
        uint256 count;
        (balances, count) = rebalancer.approveAndTransfer(
            initiator, balances, fees, initiatorParams, address(nonfungiblePositionManager), position
        );

        // Then: It should return the correct count.
        assertEq(count, 3);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(rebalancer), account_), balances[0]);
        assertEq(token1.allowance(address(rebalancer), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), fee1);
    }
}
