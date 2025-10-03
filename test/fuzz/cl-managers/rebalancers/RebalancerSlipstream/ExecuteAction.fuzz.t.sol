/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { DefaultRebalancerHook } from "../../../../utils/mocks/DefaultRebalancerHook.sol";
import { ERC20, ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceMock } from "../../../../utils/mocks/RouterSetPoolPriceMock.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "RebalancerSlipstream".
 */
contract ExecuteAction_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultRebalancerHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();

        strategyHook = new DefaultRebalancerHook();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: account is set.
        rebalancer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Rebalancer.OnlyAccount.selector);
        rebalancer.executeAction(rebalanceData);
        vm.stopPrank();
    }

    function testFuzz_Revert_executeAction_InvalidClaimFee(
        address initiator,
        Rebalancer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            maxClaimFee,
            maxSwapFee,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: claimfee is bigger than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, maxClaimFee + 1, type(uint64).max));

        // And: account is set.
        rebalancer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        address initiator,
        Rebalancer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            maxClaimFee,
            maxSwapFee,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: claimfee is smaller than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, maxClaimFee));

        // And: swapFee is bigger than maxSwapFee.
        initiatorParams.swapFee = uint64(bound(initiatorParams.swapFee, maxSwapFee + 1, type(uint64).max));

        // And: account is set.
        rebalancer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.executeAction(actionTargetData);
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
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = MAX_FEE;

        // And: A new position with a valid tick range above current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent, BOUND_TICK_UPPER - 1));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, type(uint16).max));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, type(uint16).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is unbalanced.
        {
            (, uint256 lowerSqrtPriceDeviation,,,,) = rebalancer.accountInfo(address(account));
            initiatorParams.trustedSqrtPrice = bound(
                initiatorParams.trustedSqrtPrice,
                position.sqrtPrice * 1e18 / lowerSqrtPriceDeviation + lowerSqrtPriceDeviation,
                type(uint160).max
            );
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.UnbalancedPool.selector);
        rebalancer.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolAfterSwap(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = MAX_FEE;

        // And: A new position with a valid tick range above current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent, BOUND_TICK_UPPER - 1));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );
        /// forge-lint: disable-end(erc20-unchecked-transfer)

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: The pool is unbalanced after the swap.
        {
            (, uint256 lowerSqrtPriceDeviation,,,,) = rebalancer.accountInfo(address(account));
            uint256 lowerBoundSqrtPrice = initiatorParams.trustedSqrtPrice * lowerSqrtPriceDeviation / 1e18;
            uint256 newSqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, lowerBoundSqrtPrice);

            RouterSetPoolPriceMock router = new RouterSetPoolPriceMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterSetPoolPriceMock.swap.selector, address(poolCl), uint160(newSqrtPrice));
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.UnbalancedPool.selector);
        rebalancer.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_InsufficientLiquidity(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            1e18,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = MAX_FEE;

        // And: A new position with a valid tick range above current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );
        /// forge-lint: disable-end(erc20-unchecked-transfer)

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is not optimal resulting in little liquidity.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InsufficientLiquidity.selector);
        rebalancer.executeAction(actionTargetData);
    }

    function testFuzz_Success_executeAction_Slipstream_ZeroToOne(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );
        /// forge-lint: disable-end(erc20-unchecked-transfer)

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token1), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(slipstreamPositionManager), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);
        if (depositData.assets.length == 3) {
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(slipstreamPositionManager)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        if (depositData.assets.length == 3) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_Slipstream_OneToZero(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range above current tick.
        tickLower = int24(bound(tickLower, position.tickCurrent + 1, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );
        /// forge-lint: disable-end(erc20-unchecked-transfer)

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token0), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(slipstreamPositionManager), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        if (depositData.assets.length == 2) {
            assertEq(depositData.assets[1], address(token1));
            assertEq(depositData.assetIds[1], 0);
            assertGt(depositData.assetAmounts[1], 0);
            assertEq(depositData.assetTypes[1], 1);
        } else {
            assertEq(depositData.assets[1], address(token0));
            assertEq(depositData.assetIds[1], 0);
            assertGt(depositData.assetAmounts[1], 0);
            assertEq(depositData.assetTypes[1], 1);
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(slipstreamPositionManager)).getApproved(position.id + 1), address(account));
        if (depositData.assets.length == 2) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        } else {
            assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token1.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token1), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(stakedSlipstreamAM), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        uint256 length = depositData.assets.length;
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);
        if (length == 4) {
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }
        assertEq(depositData.assets[length - 1], AERO);
        assertEq(depositData.assetIds[length - 1], 0);
        assertGt(depositData.assetAmounts[length - 1], 0);
        assertEq(depositData.assetTypes[length - 1], 1);

        // And: Approvals are given.
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        if (length == 4) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }
        assertEq(ERC20(AERO).allowance(address(rebalancer), address(account)), depositData.assetAmounts[length - 1]);

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: Aero is an underlying token of the position.
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), rewards, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token1), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(stakedSlipstreamAM), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        uint256 length = depositData.assets.length;
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);
        if (length == 3) {
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        if (length == 3) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(wrappedStakedSlipstream);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token1), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(wrappedStakedSlipstream), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        uint256 length = depositData.assets.length;
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);
        if (length == 4) {
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }
        assertEq(depositData.assets[length - 1], AERO);
        assertEq(depositData.assetIds[length - 1], 0);
        assertGt(depositData.assetAmounts[length - 1], 0);
        assertEq(depositData.assetTypes[length - 1], 1);

        // And: Approvals are given.
        assertEq(ERC721(address(wrappedStakedSlipstream)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        if (length == 4) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }
        assertEq(ERC20(AERO).allowance(address(rebalancer), address(account)), depositData.assetAmounts[length - 1]);

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: Aero is an underlying token of the position.
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        setPositionState(position);
        initiatorParams.positionManager = address(wrappedStakedSlipstream);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), rewards, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A new position with a valid tick range below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickCurrent - 11));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, position.tickCurrent - 1));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: The Rebalancer owns the position.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Rebalancer has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        deal(address(token0), address(rebalancer), initiatorParams.amount0, true);
        deal(address(token1), address(rebalancer), initiatorParams.amount1, true);

        // And: account is set.
        rebalancer.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, type(uint72).max);
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
            deal(address(token1), address(router), type(uint72).max, true);
        }

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(wrappedStakedSlipstream), position.id, position.id + 1);
        ActionData memory depositData = rebalancer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        uint256 length = depositData.assets.length;
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);
        if (length == 3) {
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(wrappedStakedSlipstream)).getApproved(position.id + 1), address(account));
        assertEq(token0.allowance(address(rebalancer), address(account)), depositData.assetAmounts[1]);
        if (length == 3) {
            assertEq(token1.allowance(address(rebalancer), address(account)), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (initiatorParams.claimFee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }
}
