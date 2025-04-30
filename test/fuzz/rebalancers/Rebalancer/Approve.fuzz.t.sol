/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";

/**
 * @notice Fuzz tests for the function "_approve" of contract "Rebalancer".
 */
contract Approve_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
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
    function testFuzz_Success_approve_AllZero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position
    ) public {
        // Given: rebalancer has zero balances.
        uint256[] memory balances = new uint256[](2);
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: Uniswap v3 position.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approve().
        vm.prank(account_);
        uint256 count = rebalancer.approve(balances, initiatorParams, position);

        // Then: It should return the correct count.
        assertEq(count, 1);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are not approved.
        assertEq(token0.allowance(address(rebalancer), account_), 0);
        assertEq(token1.allowance(address(rebalancer), account_), 0);
    }

    function testFuzz_Success_approve_Token1Zero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        uint256 balance0
    ) public {
        // Given: rebalancer has non zero balances.
        balance0 = bound(balance0, 1, type(uint256).max);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: Uniswap v3 position.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approve().
        vm.prank(account_);
        uint256 count = rebalancer.approve(balances, initiatorParams, position);

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(token0.allowance(address(rebalancer), account_), balance0);
        assertEq(token1.allowance(address(rebalancer), account_), 0);
    }

    function testFuzz_Success_approve_Token0Zero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        uint256 balance1
    ) public {
        // Given: rebalancer has non zero balances.
        balance1 = bound(balance1, 1, type(uint256).max);
        uint256[] memory balances = new uint256[](2);
        balances[1] = balance1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: Uniswap v3 position.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approve().
        vm.prank(account_);
        uint256 count = rebalancer.approve(balances, initiatorParams, position);

        // Then: It should return the correct count.
        assertEq(count, 2);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(token0.allowance(address(rebalancer), account_), 0);
        assertEq(token1.allowance(address(rebalancer), account_), balance1);
    }

    function testFuzz_Success_approve_AllNonZero(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        uint256 balance0,
        uint256 balance1
    ) public {
        // Given: rebalancer has non zero balances.
        balance0 = bound(balance0, 1, type(uint256).max);
        balance1 = bound(balance1, 1, type(uint256).max);
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: Uniswap v3 position.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        nonfungiblePositionManager.mint(address(rebalancer), position.id);

        // When: Calling _approve().
        vm.prank(account_);
        uint256 count = rebalancer.approve(balances, initiatorParams, position);

        // Then: It should return the correct count.
        assertEq(count, 3);

        // And: The position is approved.
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(position.id), address(account_));

        // And: ERC20 tokens are approved.
        assertEq(token0.allowance(address(rebalancer), account_), balance0);
        assertEq(token1.allowance(address(rebalancer), account_), balance1);
    }
}
