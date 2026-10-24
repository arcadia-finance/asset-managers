/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { ILeafVoter } from "../../../../../lib/accounts-v2/test/utils/fixtures/metadex03/interfaces/ILeafVoter.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimerMetadexCL_Fuzz_Test } from "./_YieldClaimerMetadexCL.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimerSlipstream", on Metadex CL.
 */
contract Claim_YieldClaimerMetadexCL_Fuzz_Test is YieldClaimerMetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimerMetadexCL_Fuzz_Test.setUp();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a pool with an in range position that carries both tokens.
    function setInRangePosition(uint128 liquidityPool, PositionState memory position, bool staked) internal {
        givenValidPoolState(liquidityPool, position);
        // forge-lint: disable-next-item(unsafe-typecast)
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, staked);
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        // forge-lint: disable-next-item(unsafe-typecast)
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
    }

    function allowYieldClaimerAsAssetManager() internal {
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(yieldClaimer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
    }

    function depositInAccount(address positionManager, PositionState memory position) internal {
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);

        assets_[0] = positionManager;
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;

        vm.startPrank(users.accountOwner);
        ERC721(positionManager).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_claim_Paused(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: YieldClaimer is paused.
        vm.prank(users.owner);
        yieldClaimer.setPauseFlag(true);

        // When: Calling claim.
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        // Then: It reverts.
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_Reentered(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: Calling claim.
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        // Then: It reverts.
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidInitiator(YieldClaimer.InitiatorParams memory initiatorParams, address caller)
        public
    {
        // Given: Caller is not address(0).
        vm.assume(caller != address(0));

        // And: The owner of the account has not set an initiator yet.

        // When: Calling claim.
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        // Then: It reverts.
        yieldClaimer.claim(address(account), initiatorParams);
    }

    function testFuzz_Success_claim_MetadexCL_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Initiator is not holding balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.id = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: YieldClaimer is allowed as Asset Manager.
        allowYieldClaimerAsAssetManager();

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmountsMetadex03CL(position.id);

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(metadex03PositionManager), position);

        // When: Calling claim.
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(account));

        // And: The tokens are deposited back into the account.
        assertEq(token0.balanceOf(address(account)), fee0 - fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(address(account)), fee1 - fee1 * initiatorParams.claimFee / 1e18);

        // And: The initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_claim_StakedMetadexCLAM_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        vm.assume(initiator != address(0));

        // Given: Initiator is not holding balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.id = uint96(position.id);

        // And: YieldClaimer is allowed as Asset Manager.
        allowYieldClaimerAsAssetManager();

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));
        rewards = stakedMetadex03CLAM.rewardOf(position.id);

        // And: Account owns the staked position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(stakedMetadex03CLAM), position);

        // When: Calling claim.
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(stakedMetadex03CLAM)).ownerOf(position.id), address(account));

        // And: The ReceiptToken rewards are deposited back into the account.
        assertEq(ERC20(receiptToken).balanceOf(address(account)), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: The initiator fees are given.
        assertEq(ERC20(receiptToken).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_claim_StakedMetadexCLAM_PenaltyWindow(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 emissions,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        address initiator
    ) public {
        // Given: Initiator is not holding balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        YieldClaimer.InitiatorParams memory initiatorParams;
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.id = uint96(position.id);

        // And: YieldClaimer is allowed as Asset Manager.
        allowYieldClaimerAsAssetManager();

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Account info is set, the initiator takes no fee.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

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
        assertEq(stakedMetadex03CLAM.rewardOf(position.id), netExpected);

        // And: Account owns the staked position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(stakedMetadex03CLAM), position);

        // When: Calling claim.
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The account receives the net reward, never the gross.
        assertEq(ERC20(receiptToken).balanceOf(address(account)), netExpected);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Revert_claim_StakedMetadexCLAM_ChainSuspended(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 emissions,
        address initiator
    ) public {
        // Given: Initiator is not holding balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        YieldClaimer.InitiatorParams memory initiatorParams;
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.id = uint96(position.id);

        // And: YieldClaimer is allowed as Asset Manager.
        allowYieldClaimerAsAssetManager();

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: The position earned emissions.
        emissions = bound(emissions, 1e18, type(uint96).max);
        addEmissionsToGauge(address(gauge), emissions);
        vm.warp(block.timestamp + 1);
        vm.assume(stakedMetadex03CLAM.rewardOf(position.id) > 0);

        // And: Account owns the staked position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(stakedMetadex03CLAM), position);

        // And: The chain is suspended.
        setChainSuspended(true);

        // When: Calling claim.
        vm.prank(initiator);
        vm.expectRevert(ILeafVoter.ChainNotActiveOrSunset.selector);
        // Then: It reverts.
        yieldClaimer.claim(address(account), initiatorParams);
    }
}
