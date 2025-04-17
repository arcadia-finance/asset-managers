/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/token-claimers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "claimAero" of contract "AeroClaimer".
 */
contract ClaimAero_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        AeroClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_claimAero_Reentered(address random, uint256 tokenId) public {
        // Given: An account address is defined in storage.
        aeroClaimer.setAccount(random);

        // When: Calling claimAero().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.Reentered.selector);
        aeroClaimer.claimAero(address(account), tokenId);
    }

    function testFuzz_Revert_claimAero_InitiatorNotValid(address notInitiator, uint256 tokenId) public {
        // Given: The caller is not the initiator.
        vm.assume(initiator != notInitiator);

        // When: Calling claimAero().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(AeroClaimer.InitiatorNotValid.selector);
        aeroClaimer.claimAero(address(account), tokenId);
    }

    function testFuzz_Success_claimAero(
        StakedSlipstreamAM.PositionState memory position,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        int24 tick
    ) public {
        // Given : a valid position.
        position = givenValidPosition(position, 1);

        // And : the current tick of the pool is in range (can't be equal to tickUpper, but can be equal to tickLower).
        tick = int24(bound(tick, position.tickLower, position.tickUpper - 1));
        deployAndAddGauge(tick);

        // Given : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // And : assetId is minted.
        uint256 assetId = addLiquidity(position);

        // And: Position is staked.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), assetId);
        stakedSlipstreamAM.mint(assetId);
        vm.stopPrank();

        // And: Transfer the position to the Account owner and deposit in Account
        {
            vm.prank(users.liquidityProvider);
            stakedSlipstreamAM.transferFrom(users.liquidityProvider, users.accountOwner, assetId);

            address[] memory assets_ = new address[](1);
            assets_[0] = address(stakedSlipstreamAM);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = assetId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(stakedSlipstreamAM)).approve(address(account), assetId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Rewards are earned.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // And : Rewards amount is not zero.
        uint256 rewardGrowthInsideX128;
        unchecked {
            rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
        }
        uint256 liquidity = getActualLiquidity(position);
        uint256 rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, liquidity, FixedPoint128.Q128);
        // Expect minimum rewards to not have 0 initiator fee.
        vm.assume(rewardsExpected > 1e4);
        // Avoid overflow in amountClaimed * fee, rewards would be irrealistically high.
        vm.assume(rewardsExpected < type(uint128).max);

        // When : An initiator claims pending Aero from staked slipstream position in Account.
        vm.startPrank(initiator);
        vm.expectEmit();
        emit AeroClaimer.AeroClaimed(address(account), assetId);
        aeroClaimer.claimAero(address(account), assetId);
        vm.stopPrank();

        // Then : Account should still own the position.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(assetId), address(account));
        // And : Account should have received AERO.
        uint256 expectedInitiatorShare = rewardsExpected.mulDivDown(INITIATOR_SHARE, 1e18);
        uint256 expectedAccountBalance = rewardsExpected - expectedInitiatorShare;
        assertEq(ERC20(AERO).balanceOf(initiator), expectedInitiatorShare);
        assertGt(ERC20(AERO).balanceOf(initiator), 0);
        // And : The initiator should have received its share
        assertEq(ERC20(AERO).balanceOf(address(account)), expectedAccountBalance);
        assertGt(ERC20(AERO).balanceOf(address(account)), 0);
    }
}
