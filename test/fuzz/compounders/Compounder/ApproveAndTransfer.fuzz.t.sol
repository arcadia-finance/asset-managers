/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AbstractBase } from "../../../../src/base/AbstractBase.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Compounder } from "../../../../src/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";

/**
 * @notice Fuzz tests for the function "_approveAndTransfer" of contract "Compounder".
 */
contract ApproveAndTransfer_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(Compounder_Fuzz_Test) {
        Compounder_Fuzz_Test.setUp();

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_approveAndTransfer_AllZero(
        address account_,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(compounder));

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

        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(compounder), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        uint256 count;
        (balances, count) =
            compounder.approveAndTransfer(initiator, balances, fees, address(nonfungiblePositionManager), position);

        // Then: It should return the correct count.
        assertEq(count, 1);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(compounder), account_), 0);
        assertEq(token1.allowance(address(compounder), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_Token1Zero(
        address account_,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(compounder));

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

        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(compounder), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), balance1);
        vm.prank(account_);
        uint256 count;
        (balances, count) =
            compounder.approveAndTransfer(initiator, balances, fees, address(nonfungiblePositionManager), position);

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], 0);
        assertEq(token0.allowance(address(compounder), account_), balances[0]);
        assertEq(token1.allowance(address(compounder), account_), 0);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), balance1);
    }

    function testFuzz_Success_approveAndTransfer_Token0Zero(
        address account_,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(compounder));

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

        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(compounder), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), balance0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
        vm.prank(account_);
        uint256 count;
        (balances, count) =
            compounder.approveAndTransfer(initiator, balances, fees, address(nonfungiblePositionManager), position);

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], 0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(compounder), account_), 0);
        assertEq(token1.allowance(address(compounder), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), balance0);
        assertEq(token1.balanceOf(initiator), fee1);
    }

    function testFuzz_Success_approveAndTransfer_AllNonZero(
        address account_,
        PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 fee0,
        uint256 fee1,
        address initiator
    ) public {
        // Given: The initiator is not the contract.
        vm.assume(initiator != address(compounder));

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

        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Uniswap v3 position.
        nonfungiblePositionManager.mint(address(compounder), position.id);

        // When: Calling _approveAndTransfer().
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.FeePaid(account_, initiator, address(token1), fee1);
        vm.prank(account_);
        uint256 count;
        (balances, count) =
            compounder.approveAndTransfer(initiator, balances, fees, address(nonfungiblePositionManager), position);

        // Then: It should return the correct count.
        assertEq(count, 3);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(balances[0], balance0 - fee0);
        assertEq(balances[1], balance1 - fee1);
        assertEq(token0.allowance(address(compounder), account_), balances[0]);
        assertEq(token1.allowance(address(compounder), account_), balances[1]);

        // And: The initiator should have received the fees
        assertEq(token0.balanceOf(initiator), fee0);
        assertEq(token1.balanceOf(initiator), fee1);
    }
}
