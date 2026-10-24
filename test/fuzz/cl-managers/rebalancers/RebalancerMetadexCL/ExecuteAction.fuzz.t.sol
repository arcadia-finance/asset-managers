/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { DefaultRebalancerHook } from "../../../../utils/mocks/DefaultRebalancerHook.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { RebalancerMetadexCL_Fuzz_Test } from "./_RebalancerMetadexCL.fuzz.t.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "RebalancerSlipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ExecuteAction_RebalancerMetadexCL_Fuzz_Test is RebalancerMetadexCL_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultRebalancerHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerMetadexCL_Fuzz_Test.setUp();

        strategyHook = new DefaultRebalancerHook();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a pool with an in range position that carries both tokens.
    function setInRangePosition(uint128 liquidityPool, PositionState memory position, bool staked)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, staked);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        (amount0, amount1) = setPositionState(position);
    }

    function setAccountInfo(address initiator, uint256 tolerance) internal {
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );
    }

    // Encodes a router swap that always returns a large amountOut of tokenOut.
    function setSwapData(Rebalancer.InitiatorParams memory initiatorParams, bool zeroToOne) internal {
        RouterMock router = new RouterMock();
        (address tokenIn, address tokenOut) =
            zeroToOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, tokenIn, tokenOut, 0, type(uint72).max);
        initiatorParams.swapData = abi.encode(address(router), 0, routerData);
        deal(tokenOut, address(router), type(uint72).max, true);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: Account is set.
        rebalancer.setAccount(account_);

        // When: Calling executeAction.
        vm.prank(caller_);
        vm.expectRevert(Rebalancer.OnlyAccount.selector);
        // Then: It reverts.
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolBeforeSwap(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0, MAX_TOLERANCE));

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = MAX_FEE;

        // And: A new position with a valid tick range above the current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent, BOUND_TICK_UPPER - 1));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Rebalancer has balances.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, type(uint16).max));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, type(uint16).max));
        deal(address(token0), address(rebalancer), initiatorParams.amountIn0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amountIn1, true);

        // And: Account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is unbalanced.
        {
            (,,, uint256 lowerSqrtPriceDeviation,,) = rebalancer.accountInfo(address(account));
            initiatorParams.trustedSqrtPrice = bound(
                initiatorParams.trustedSqrtPrice,
                position.sqrtPrice * 1e18 / lowerSqrtPriceDeviation + lowerSqrtPriceDeviation,
                type(uint160).max
            );
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.UnbalancedPool.selector);
        // Then: It reverts.
        rebalancer.executeAction(abi.encode(initiator, initiatorParams));
    }

    function testFuzz_Success_executeAction_MetadexCL_ZeroToOne(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        (uint256 amount0, uint256 amount1) = setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE));

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below the current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, 1));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, 1));
        deal(address(token0), address(rebalancer), initiatorParams.amountIn0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amountIn1, true);

        // And: The withdrawn amount is smaller than the position balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap is successful.
        setSwapData(initiatorParams, true);

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(metadex03PositionManager), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The new position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(metadex03PositionManager)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
    }

    function testFuzz_Success_executeAction_MetadexCL_OneToZero(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        (uint256 amount0, uint256 amount1) = setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE));

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range above the current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent + 1, BOUND_TICK_UPPER - 11));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, 1));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, 1));
        deal(address(token0), address(rebalancer), initiatorParams.amountIn0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amountIn1, true);

        // And: The withdrawn amount is smaller than the position balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap is successful.
        setSwapData(initiatorParams, false);

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(metadex03PositionManager), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The new position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(metadex03PositionManager)).getApproved(position.id + 1), address(account));
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_executeAction_StakedMetadexCLAM_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 rewards,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        vm.assume(initiator != address(0));

        // Given: A valid staked position in range.
        (uint256 amount0, uint256 amount1) = setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        initiatorParams.oldId = uint96(position.id);

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE));

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below the current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        // forge-lint: disable-next-item(divide-before-multiply)
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the staked position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, 1));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, 1));
        deal(address(token0), address(rebalancer), initiatorParams.amountIn0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amountIn1, true);

        // And: The withdrawn amount is smaller than the position balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap is successful.
        setSwapData(initiatorParams, true);

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(stakedMetadex03CLAM), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The new staked position is returned to the account.
        assertEq(depositData.assets[0], address(stakedMetadex03CLAM));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The claimed ReceiptToken is returned as a third asset.
        uint256 rewardDeposited;
        for (uint256 i = 1; i < depositData.assets.length; ++i) {
            if (depositData.assets[i] == receiptToken) rewardDeposited = depositData.assetAmounts[i];
        }
        assertGt(rewardDeposited, 0);
        assertEq(rewardDeposited, ERC20(receiptToken).balanceOf(address(rebalancer)));
    }
}
