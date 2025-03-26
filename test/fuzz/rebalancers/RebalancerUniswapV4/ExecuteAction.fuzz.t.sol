/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData } from "../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { HookMock } from "../../../utils/mocks/HookMock.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceUniV4Mock } from "../../../utils/mocks/RouterSetPoolPriceUniV4Mock.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/uniswap-v3/UniswapV3Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "RebalancerUniswapV4".
 */
contract ExecuteAction_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
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
        vm.expectRevert(RebalancerUniswapV4.OnlyAccount.selector);
        rebalancer.executeAction(rebalanceData);
        vm.stopPrank();
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolBeforeSwap(
        address account_,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, stateView.getLiquidity(v4PoolKey.toId()) / 1e3));

        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(rebalancer)
        );

        // And: A new position with a valid tick range.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        // And: The pool is unbalanced.
        uint256 lowerBoundSqrtPriceX96;
        {
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
            lowerBoundSqrtPriceX96 = trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18;
        }
        uint256 newSqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, lowerBoundSqrtPriceX96);

        poolManager.setCurrentPrice(
            v4PoolKey.toId(), TickMath.getTickAtSqrtPrice(uint160(newSqrtPriceX96)), uint160(newSqrtPriceX96)
        );

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory swapData = "";
        bytes memory rebalanceData = encodeRebalanceData(
            address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
        );
        vm.prank(account_);
        vm.expectRevert(RebalancerUniswapV4.UnbalancedPool.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolAfterSwap(
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        address account_,
        uint256 tolerance
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 1));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(rebalancer)
        );

        // And: A new position with a valid tick range.
        // And: New Position is above current tick.
        tickLower = int24(bound(tickLower, tickCurrent, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);

        // And: The pool is unbalanced.
        uint256 lowerBoundSqrtPriceX96;
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        {
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
            lowerBoundSqrtPriceX96 = trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18;
        }

        // And: Pool is unbalanced after swap (done via router mock).
        bytes memory swapData;
        {
            uint160 sqrtPriceX96 =
                uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, lowerBoundSqrtPriceX96));

            RouterSetPoolPriceUniV4Mock router = new RouterSetPoolPriceUniV4Mock();
            bytes memory routerData = abi.encodeWithSelector(
                RouterSetPoolPriceUniV4Mock.swap.selector,
                address(poolManager),
                v4PoolKey.toId(),
                TickMath.getTickAtSqrtPrice(sqrtPriceX96),
                sqrtPriceX96
            );
            swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory rebalanceData = encodeRebalanceData(
            address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
        );
        vm.prank(account_);
        vm.expectRevert(RebalancerUniswapV4.UnbalancedPool.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_InsufficientLiquidity(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));
        vm.assume(account_ != address(this));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 1));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = tickCurrent + (tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(rebalancer)
        );

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id)));
        position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

        // And: A new position with a valid tick range.
        // And: New Position is above current tick.
        tickLower = int24(bound(tickLower, tickCurrent, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);

        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;

        // And: Swap is not optimal resulting in little liquidity.
        bytes memory swapData;
        {
            RouterMock router = new RouterMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
            swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory rebalanceData = encodeRebalanceData(
            address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
        );
        vm.prank(account_);
        vm.expectRevert(RebalancerUniswapV4.InsufficientLiquidity.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Success_executeAction_ZeroToOne(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        uint256 id;
        {
            int24 tickSpacing = TICK_SPACING;

            // And: A valid position with multiple tickSpacing.
            // And: Position is in range (has both tokens).
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
            position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
            position.tickLower = position.tickLower / tickSpacing * tickSpacing;
            position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
            position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
            position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

            id = mintPositionV4(
                v4PoolKey,
                position.tickLower,
                position.tickUpper,
                position.liquidity,
                type(uint128).max,
                type(uint128).max,
                address(rebalancer)
            );

            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

            // And: A new position with a valid tick range.
            // And: New Position is below current tick.
            tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 2));
            tickLower = tickLower / tickSpacing * tickSpacing;
            tickUpper = int24(bound(tickUpper, tickLower + 1, tickCurrent - 1));
            tickUpper = tickUpper / tickSpacing * tickSpacing;
        }

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        ActionData memory depositData;
        {
            bytes memory rebalanceData;
            {
                // And: Swap is successful.
                deal(address(token1), address(rebalancer), type(uint72).max, true);
                bytes memory swapData;
                {
                    RouterMock router = new RouterMock();
                    bytes memory routerData =
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData = encodeRebalanceData(
                    address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
                );
            }

            int24 tickLowerStack = tickLower;
            int24 tickUpperStack = tickUpper;

            // And: Hook is set.
            HookMock hook = new HookMock();
            rebalancer.setHook(account_, address(hook));

            // When: Calling executeAction().
            // Then: Hook should be called.
            vm.prank(account_);
            vm.expectEmit();
            emit RebalancerUniswapV4.Rebalance(account_, address(positionManagerV4), id, id + 1);
            vm.expectCall(
                address(hook),
                abi.encodeWithSelector(
                    hook.beforeRebalance.selector,
                    account_,
                    address(positionManagerV4),
                    id,
                    tickLowerStack,
                    tickUpperStack
                )
            );
            vm.expectCall(
                address(hook),
                abi.encodeWithSelector(hook.afterRebalance.selector, account_, address(positionManagerV4), id, id + 1)
            );
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], address(token0));
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);

        // And: Approvals are given.
        assertEq(ERC721(address(positionManagerV4)).getApproved(id + 1), account_);
        assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_OneToZero(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(rebalancer)
        );

        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);
        }

        // And: A new position with a valid tick range.
        // And: New Position is above current tick.
        tickLower = int24(bound(tickLower, tickCurrent + 1, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        ActionData memory depositData;
        {
            // And: Swap is successful.
            deal(address(token0), address(rebalancer), type(uint72).max, true);
            bytes memory swapData;
            {
                RouterMock router = new RouterMock();
                bytes memory routerData =
                    abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                swapData = abi.encode(address(router), 0, routerData);
            }

            // When: Calling executeAction().
            bytes memory rebalanceData = encodeRebalanceData(
                address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
            );
            vm.prank(account_);
            vm.expectEmit();
            emit RebalancerUniswapV4.Rebalance(account_, address(positionManagerV4), id, id + 1);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], id + 1);
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
        assertEq(ERC721(address(positionManagerV4)).getApproved(id + 1), account_);
        if (depositData.assets.length == 2) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        } else {
            assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token1.balanceOf(initiator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        NATIVE ETH FLOW
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_executeAction_ZeroToOne_NativeETH(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        uint256 id;
        {
            int24 tickSpacing = TICK_SPACING;

            // And: A valid position with multiple tickSpacing.
            // And: Position is in range (has both tokens).
            (, int24 tickCurrent,,) = stateView.getSlot0(nativeEthPoolKey.toId());
            position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
            position.tickLower = position.tickLower / tickSpacing * tickSpacing;
            position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
            position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
            position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

            id = mintPositionV4(
                nativeEthPoolKey,
                position.tickLower,
                position.tickUpper,
                position.liquidity,
                type(uint128).max,
                type(uint128).max,
                address(rebalancer)
            );

            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            position.liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);

            // And: A new position with a valid tick range.
            // And: New Position is below current tick.
            // And : We slightly increase minium tick range to 10 in this case to avoid TickLiqudityOverflow,
            // but this is covered by above similar test without native ETH and should in theory never be the case.
            tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
            tickLower = tickLower / tickSpacing * tickSpacing;
            tickUpper = int24(bound(tickUpper, tickLower + 10, tickCurrent - 1));
            tickUpper = tickUpper / tickSpacing * tickSpacing;
        }

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        ActionData memory depositData;
        {
            bytes memory rebalanceData;
            {
                // And: Swap is successful.
                deal(address(token1), address(rebalancer), type(uint72).max, true);
                bytes memory swapData;
                {
                    RouterMock router = new RouterMock();
                    bytes memory routerData =
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData = encodeRebalanceData(
                    address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
                );
            }

            int24 tickLowerStack = tickLower;
            int24 tickUpperStack = tickUpper;

            // And: Hook is set.
            HookMock hook = new HookMock();
            rebalancer.setHook(account_, address(hook));

            // When: Calling executeAction().
            // Then: Hook should be called.
            vm.prank(account_);
            vm.expectEmit();
            emit RebalancerUniswapV4.Rebalance(account_, address(positionManagerV4), id, id + 1);
            vm.expectCall(
                address(hook),
                abi.encodeWithSelector(
                    hook.beforeRebalance.selector,
                    account_,
                    address(positionManagerV4),
                    id,
                    tickLowerStack,
                    tickUpperStack
                )
            );
            vm.expectCall(
                address(hook),
                abi.encodeWithSelector(hook.afterRebalance.selector, account_, address(positionManagerV4), id, id + 1)
            );
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], WETH);
        assertEq(depositData.assetIds[1], 0);
        assertGt(depositData.assetAmounts[1], 0);
        assertEq(depositData.assetTypes[1], 1);

        // And: Approvals are given.
        assertEq(ERC721(address(positionManagerV4)).getApproved(id + 1), account_);
        assertEq(ERC20(WETH).allowance(address(rebalancer), account_), depositData.assetAmounts[1]);

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(initiator.balance, 0);
    }

    function testFuzz_Success_executeAction_OneToZero_NativeETH(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

        uint256 id = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(rebalancer)
        );

        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            position.liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
        }

        // And: A new position with a valid tick range.
        // And: New Position is above current tick.
        tickLower = int24(bound(tickLower, tickCurrent + 1, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And: account is set.
        rebalancer.setAccount(account_);

        ActionData memory depositData;
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        {
            // And: Swap is successful.
            vm.deal(address(rebalancer), type(uint72).max);
            bytes memory swapData;
            {
                RouterMock router = new RouterMock();
                bytes memory routerData =
                    abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                swapData = abi.encode(address(router), 0, routerData);
            }

            // When: Calling executeAction().
            bytes memory rebalanceData = encodeRebalanceData(
                address(positionManagerV4), id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
            );
            vm.prank(account_);
            vm.expectEmit();
            emit RebalancerUniswapV4.Rebalance(account_, address(positionManagerV4), id, id + 1);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], id + 1);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        if (depositData.assets.length == 2) {
            assertEq(depositData.assets[1], address(token1));
            assertEq(depositData.assetIds[1], 0);
            assertGt(depositData.assetAmounts[1], 0);
            assertEq(depositData.assetTypes[1], 1);
        } else {
            assertEq(depositData.assets[1], WETH);
            assertEq(depositData.assetIds[1], 0);
            assertGt(depositData.assetAmounts[1], 0);
            assertEq(depositData.assetTypes[1], 1);
            assertEq(depositData.assets[2], address(token1));
            assertEq(depositData.assetIds[2], 0);
            assertGt(depositData.assetAmounts[2], 0);
            assertEq(depositData.assetTypes[2], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(positionManagerV4)).getApproved(id + 1), account_);
        if (depositData.assets.length == 2) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        } else {
            assertEq(ERC20(WETH).allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token1.balanceOf(initiator), 0);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function encodeRebalanceData(
        address positionManager,
        uint256 id,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        uint256 trustedSqrtPriceX96,
        bytes memory swapData
    ) public pure returns (bytes memory rebalanceData) {
        address[] memory assets_ = new address[](1);
        assets_[0] = positionManager;
        uint256[] memory assetIds_ = new uint256[](1);
        assetIds_[0] = id;
        uint256[] memory assetAmounts_ = new uint256[](1);
        assetAmounts_[0] = 1;
        uint256[] memory assetTypes_ = new uint256[](1);
        assetTypes_[0] = 2;

        ActionData memory assetData =
            ActionData({ assets: assets_, assetIds: assetIds_, assetAmounts: assetAmounts_, assetTypes: assetTypes_ });

        rebalanceData = abi.encode(assetData, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData);
    }
}
