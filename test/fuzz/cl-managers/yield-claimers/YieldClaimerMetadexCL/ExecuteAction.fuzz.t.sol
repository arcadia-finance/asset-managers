/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimerMetadexCL_Fuzz_Test } from "./_YieldClaimerMetadexCL.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "YieldClaimerSlipstream", on Metadex CL.
 */
contract ExecuteAction_YieldClaimerMetadexCL_Fuzz_Test is YieldClaimerMetadexCL_Fuzz_Test {
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
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
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

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata claimData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: Account is set.
        yieldClaimer.setAccount(account_);

        // When: Calling executeAction.
        vm.prank(caller_);
        vm.expectRevert(YieldClaimer.OnlyAccount.selector);
        // Then: It reverts.
        yieldClaimer.executeAction(claimData);
    }

    function testFuzz_Success_executeAction_MetadexCL_AccountIsRecipient(
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

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(yieldClaimer), position.id);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmountsMetadex03CL(position.id);

        // And: Account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(metadex03PositionManager), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(metadex03PositionManager)).getApproved(position.id), address(account));
        assertEq(
            token0.allowance(address(yieldClaimer), address(account)), fee0 - fee0 * initiatorParams.claimFee / 1e18
        );
        assertEq(
            token1.allowance(address(yieldClaimer), address(account)), fee1 - fee1 * initiatorParams.claimFee / 1e18
        );

        // And: The initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_executeAction_StakedMetadexCLAM_AccountIsRecipient(
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

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        // forge-lint: disable-next-item(unsafe-typecast)
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the staked position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(yieldClaimer), position.id);

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));
        rewards = stakedMetadex03CLAM.rewardOf(position.id);

        // And: Account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(stakedMetadex03CLAM), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The staked position is returned to the account.
        assertEq(depositData.assets[0], address(stakedMetadex03CLAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The ReceiptToken is returned as a third asset.
        assertEq(depositData.assets[1], receiptToken);
        assertEq(depositData.assetIds[1], 0);
        assertEq(depositData.assetAmounts[1], rewards - rewards * initiatorParams.claimFee / 1e18);
        assertEq(depositData.assetTypes[1], 1);

        // And: The initiator fee is given.
        assertEq(ERC20(receiptToken).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }
}
