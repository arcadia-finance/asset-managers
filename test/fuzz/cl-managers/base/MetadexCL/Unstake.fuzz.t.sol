/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "_unstake" of contract "Slipstream", on Metadex CL.
 */
contract Unstake_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_unstake_MetadexCL(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // And: Position is transferred to Base.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling unstake.
        balances = base.unstake(balances, address(metadex03PositionManager), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_unstake_StakedMetadexCLAM_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthDeltaX128
    ) public {
        // Given: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: An initial rewardGrowthGlobalX128.
        setRewardGrowthGlobalX128(rewardGrowthGlobalX128Last);

        // And: The position is staked and transferred to Base.
        stakeInStakedMetadexCLAM(position.id);
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Base has balances.
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // And: The position earned rewards.
        uint256 rewardGrowthGlobalX128Current;
        unchecked {
            rewardGrowthGlobalX128Current =
                rewardGrowthGlobalX128Last + givenValidRewardGrowth(position, rewardGrowthDeltaX128);
        }
        uint256 rewards = getRewards(position, rewardGrowthGlobalX128Last, rewardGrowthGlobalX128Current);
        accrueRewards(rewards, rewardGrowthGlobalX128Current);

        // When: Calling unstake.
        balances = base.unstake(balances, address(stakedMetadex03CLAM), position);

        // Then: Base should own the underlying position.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(base));

        // And: The reward is routed to the third balance.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(receiptToken).balanceOf(address(base)));
    }
}
