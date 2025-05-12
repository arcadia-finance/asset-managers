/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_stake" of contract "RebalancerSlipstream".
 */
contract Stake_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_stake_Slipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
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
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );

        // When: Calling stake.
        balances = rebalancer.stake(balances, address(slipstreamPositionManager), position);

        // Then: Rebalancer should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(rebalancer));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_stake_StakedSlipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
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
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );

        // When: Calling stake.
        balances = rebalancer.stake(balances, address(stakedSlipstreamAM), position);

        // Then: Rebalancer should own the position.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(position.id), address(rebalancer));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_stake_WrappedStakedSlipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
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
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );

        // When: Calling stake.
        balances = rebalancer.stake(balances, address(wrappedStakedSlipstream), position);

        // Then: Rebalancer should own the position.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(position.id), address(rebalancer));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }
}
