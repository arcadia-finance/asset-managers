/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../../../../../src/cl-managers/base/AbstractBase.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { ILeafVoter } from "../../../../../lib/accounts-v2/test/utils/fixtures/metadex03/interfaces/ILeafVoter.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "_claim" of contract "Slipstream", on Metadex CL.
 */
contract Claim_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_claim_MetadexCL(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint80 swap0,
        uint80 swap1,
        uint256 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        // forge-lint: disable-next-item(unsafe-typecast)
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // And: Position has fees.
        generateFees(swap0, swap1);
        (uint256 fee0, uint256 fee1) = getFeeAmountsMetadex03CL(position.id);

        // And: Position is transferred to Base.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token1), fee1);
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, address(metadex03PositionManager), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], uint256(balance0) + fee0);
        assertEq(balances[1], uint256(balance1) + fee1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], fee0 * claimFee / 1e18);
        assertEq(fees[1], fee1 * claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_claim_StakedMetadexCLAM_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthDeltaX128,
        uint64 claimFee
    ) public {
        // Given: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        // forge-lint: disable-next-item(unsafe-typecast)
        claimFee = uint64(bound(claimFee, 0, 1e18));

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

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), receiptToken, rewards);
        uint256[] memory fees = new uint256[](balances.length);
        (balances, fees) = base.claim(balances, fees, address(stakedMetadex03CLAM), position, claimFee);

        // Then: The reward is routed to the third balance.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(receiptToken).balanceOf(address(base)));

        assertEq(fees[0], 0);
        assertEq(fees[1], 0);
        assertEq(fees[2], rewards * claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_claim_StakedMetadexCLAM_PenaltyWindow(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 emissions,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint64 claimFee
    ) public {
        // Given: A valid staked position, in range.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionStateInRange(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        // forge-lint: disable-next-item(unsafe-typecast)
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: The position is staked and transferred to Base.
        stakeInStakedMetadexCLAM(position.id);
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: A penalty config is activated after onboarding, the claim falls inside the window.
        minStakeBlocks = bound(minStakeBlocks, 1, 1e6);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        metadex03CLGaugeFactory.setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: Emissions accrue after the stake.
        emissions = bound(emissions, 1e18, type(uint96).max);
        addEmissionsToGauge(address(gauge), emissions);
        vm.warp(block.timestamp + 1);

        // And: The gross reward is haircut by the penalty.
        uint256 grossReward =
            FullMath.mulDiv(FullMath.mulDiv(emissions, 1 << 128, position.liquidity), position.liquidity, 1 << 128);
        uint256 netExpected = grossReward - grossReward * penaltyRate / MAX_PIPS;

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), receiptToken, netExpected);
        uint256[] memory balances = new uint256[](3);
        uint256[] memory fees = new uint256[](3);
        (balances, fees) = base.claim(balances, fees, address(stakedMetadex03CLAM), position, claimFee);

        // Then: The net reward is credited, never the gross.
        assertEq(balances[2], netExpected);
        assertEq(balances[2], ERC20(receiptToken).balanceOf(address(base)));
        assertEq(fees[2], netExpected * claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Revert_claim_StakedMetadexCLAM_ChainSuspended(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 emissions,
        uint64 claimFee
    ) public {
        // Given: A valid staked position, in range.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionStateInRange(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        // forge-lint: disable-next-item(unsafe-typecast)
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: The position is staked and transferred to Base.
        stakeInStakedMetadexCLAM(position.id);
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: The position earned emissions.
        emissions = bound(emissions, 1e18, type(uint96).max);
        addEmissionsToGauge(address(gauge), emissions);
        vm.warp(block.timestamp + 1);
        vm.assume(stakedMetadex03CLAM.rewardOf(position.id) > 0);

        // And: The chain is suspended.
        setChainSuspended(true);

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectRevert(ILeafVoter.ChainNotActiveOrSunset.selector);
        // Then: It reverts.
        base.claim(new uint256[](3), new uint256[](3), address(stakedMetadex03CLAM), position, claimFee);
    }

    function testFuzz_Success_claim_MetadexCL_ChainSuspended(
        uint128 liquidityPool,
        PositionState memory position,
        uint80 swap0,
        uint80 swap1,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        // forge-lint: disable-next-item(unsafe-typecast)
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: Position has fees.
        generateFees(swap0, swap1);
        (uint256 fee0, uint256 fee1) = getFeeAmountsMetadex03CL(position.id);

        // And: Position is transferred to Base.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: The chain is suspended.
        setChainSuspended(true);

        // When: Calling claim.
        vm.prank(address(account));
        uint256[] memory balances;
        (balances,) =
            base.claim(new uint256[](2), new uint256[](2), address(metadex03PositionManager), position, claimFee);

        // Then: The unstaked flow is unaffected.
        assertEq(balances[0], fee0);
        assertEq(balances[1], fee1);
    }
}
