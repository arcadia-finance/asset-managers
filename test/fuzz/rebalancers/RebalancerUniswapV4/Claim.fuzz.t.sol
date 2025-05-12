/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_claim" of contract "RebalancerUniswapV4".
 */
contract Claim_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_claim_NotNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        uint256 claimFee = 0;
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // When: Calling claim.
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = rebalancer.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_claim_IsNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        uint256 claimFee = 0;
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // When: Calling claim.
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = rebalancer.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }
}
