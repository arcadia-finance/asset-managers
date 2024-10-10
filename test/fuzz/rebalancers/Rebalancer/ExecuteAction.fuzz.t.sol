/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData } from "../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { HookMock } from "../../../utils/mocks/HookMock.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/PricingLogic.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer2.fuzz.t.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceMock } from "../../../utils/mocks/RouterSetPoolPriceMock.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "Rebalancer".
 */
contract ExecuteAction_SwapLogic_Fuzz_Test is Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller != account_);

        // And: account is set.
        rebalancer.setAccount(account_);
        // When: Calling executeAction().
        // Then: it should revert.
        vm.expectRevert(Rebalancer.OnlyAccount.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolBeforeSwap(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        int24 tickSpacing = poolUniswap.tickSpacing();

        // And: A valid position with multiple tickSpacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // And: A new position with a valid tick range.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

        // And: The pool is unbalanced.
        uint256 lowerBoundSqrtPriceX96;
        {
            uint256 price0 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            uint256 price1 = 1e18;
            uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
            lowerBoundSqrtPriceX96 = trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18;
        }
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_RATIO, lowerBoundSqrtPriceX96);
        poolUniswap.setSqrtPriceX96(uint160(position.sqrtPriceX96));

        // And: caller is the account.
        rebalancer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory swapData = "";
        bytes memory rebalanceData =
            encodeRebalanceData(address(nonfungiblePositionManager), id, initiator, tickLower, tickUpper, swapData);
        vm.prank(account_);
        vm.expectRevert(Rebalancer.UnbalancedPool.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolAfterSwap(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        int24 tickSpacing = poolUniswap.tickSpacing();

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 1));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // And: A new position with a valid tick range.
        // And: New Position is above current tick.
        tickLower = int24(bound(tickLower, tickCurrent, BOUND_TICK_UPPER - 10));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10, BOUND_TICK_UPPER));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

        // And: The pool is unbalanced.
        uint256 lowerBoundSqrtPriceX96;
        {
            uint256 price0 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            uint256 price1 = 1e18;
            uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
            lowerBoundSqrtPriceX96 = trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18;
        }
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_RATIO, lowerBoundSqrtPriceX96);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

        // And: Pool is unbalanced after swap (done via router mock).
        bytes memory swapData;
        {
            RouterSetPoolPriceMock router = new RouterSetPoolPriceMock();
            bytes memory routerData = abi.encodeWithSelector(
                RouterSetPoolPriceMock.swap.selector, address(poolUniswap), uint160(position.sqrtPriceX96)
            );
            swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory rebalanceData =
            encodeRebalanceData(address(nonfungiblePositionManager), id, initiator, tickLower, tickUpper, swapData);
        vm.prank(account_);
        vm.expectRevert(Rebalancer.UnbalancedPool.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Revert_executeAction_InsufficientLiquidity(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        int24 tickSpacing = poolUniswap.tickSpacing();

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 1));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = tickCurrent + (tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(rebalancer), id);

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
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
        bytes memory rebalanceData =
            encodeRebalanceData(address(nonfungiblePositionManager), id, initiator, tickLower, tickUpper, swapData);
        vm.prank(account_);
        vm.expectRevert(Rebalancer.InsufficientLiquidity.selector);
        rebalancer.executeAction(rebalanceData);
    }

    function testFuzz_Success_executeAction_ZeroToOne(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        int24 tickSpacing = poolUniswap.tickSpacing();

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // And: A new position with a valid tick range.
        // And: New Position is below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 2));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, tickCurrent - 1));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData = encodeRebalanceData(
                    address(nonfungiblePositionManager), id, initiator, tickLower, tickUpper, swapData
                );
            }

            // And: Hook is set.
            HookMock hook = new HookMock();
            rebalancer.setHook(account_, address(hook));

            // When: Calling executeAction().
            // Then: Hook should be called.
            vm.prank(account_);
            vm.expectCall(
                address(hook),
                abi.encodeWithSelector(hook.afterRebalance.selector, address(nonfungiblePositionManager), id, id + 1)
            );
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
        assertEq(depositData.assetIds[0], id + 1);
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
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(id + 1), account_);
        assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        if (depositData.assets.length == 3) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_OneToZero(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        int24 tickSpacing = poolUniswap.tickSpacing();

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(rebalancer), id);

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
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
            bytes memory rebalanceData =
                encodeRebalanceData(address(nonfungiblePositionManager), id, initiator, tickLower, tickUpper, swapData);
            vm.prank(account_);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
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
        assertEq(ERC721(address(nonfungiblePositionManager)).getApproved(id + 1), account_);
        if (depositData.assets.length == 2) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        } else {
            assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token1.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_Slipstream(
        address account_,
        Rebalancer.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool, TICK_SPACING);

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 1));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 1, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityCL(
            poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // And: A new position with a valid tick range.
        // And: New Position is below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 11));
        tickLower = tickLower / TICK_SPACING * TICK_SPACING;
        tickUpper = int24(bound(tickUpper, tickLower + 10, tickCurrent - 1));
        tickUpper = tickUpper / TICK_SPACING * TICK_SPACING;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData = encodeRebalanceData(
                    address(slipstreamPositionManager), id, initiator, tickLower, tickUpper, swapData
                );
            }

            // When: Calling executeAction().
            vm.prank(account_);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], id + 1);
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
        assertEq(ERC721(address(slipstreamPositionManager)).getApproved(id + 1), account_);
        assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        if (depositData.assets.length == 3) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenNotToken0Or1(
        Rebalancer.PositionState memory position,
        address account_,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee,
        uint256 rewards
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitStakedSlipstream(uint160(position.sqrtPriceX96), liquidityPool, TICK_SPACING, false);

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 11));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityCL(
            poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), id);
        stakedSlipstreamAM.mint(id);
        vm.stopPrank();
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), id);

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

        // And: A new position with a valid tick range.
        // And: New Position is below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 11));
        tickLower = tickLower / TICK_SPACING * TICK_SPACING;
        tickUpper = int24(bound(tickUpper, tickLower + 10, tickCurrent - 1));
        tickUpper = tickUpper / TICK_SPACING * TICK_SPACING;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData =
                    encodeRebalanceData(address(stakedSlipstreamAM), id, initiator, tickLower, tickUpper, swapData);
            }

            // When: Calling executeAction().
            vm.prank(account_);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        uint256 length = depositData.assets.length;
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], id + 1);
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
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(id + 1), account_);
        assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        if (depositData.assets.length == 4) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }
        assertEq(ERC20(AERO).allowance(address(rebalancer), account_), depositData.assetAmounts[length - 1]);

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token0.balanceOf(initiator), 0);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenIsToken0Or1(
        Rebalancer.PositionState memory position,
        address account_,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee,
        uint256 rewards
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        deployAndInitStakedSlipstream(uint160(position.sqrtPriceX96), liquidityPool, TICK_SPACING, true);

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 11));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));
        (uint256 id,,) = addLiquidityCL(
            poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), id);
        stakedSlipstreamAM.mint(id);
        vm.stopPrank();
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint64).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint64).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }

        // And: A new position with a valid tick range.
        // And: New Position is below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 11));
        tickLower = tickLower / TICK_SPACING * TICK_SPACING;
        tickUpper = int24(bound(tickUpper, tickLower + 10, tickCurrent - 1));
        tickUpper = tickUpper / TICK_SPACING * TICK_SPACING;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee);

        // And: Caller is the account.
        rebalancer.setAccount(account_);

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
                        abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), 0, 0);
                    swapData = abi.encode(address(router), 0, routerData);
                }

                rebalanceData =
                    encodeRebalanceData(address(stakedSlipstreamAM), id, initiator, tickLower, tickUpper, swapData);
            }

            // When: Calling executeAction().
            vm.prank(account_);
            depositData = rebalancer.executeAction(rebalanceData);
        }

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], id + 1);
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
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(id + 1), account_);
        assertEq(token0.allowance(address(rebalancer), account_), depositData.assetAmounts[1]);
        if (depositData.assets.length == 3) {
            assertEq(token1.allowance(address(rebalancer), account_), depositData.assetAmounts[2]);
        }

        // And: Initiator fees are given.
        if (fee > 1e16) assertGt(token0.balanceOf(initiator), 0);
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

        rebalanceData = abi.encode(assetData, initiator, tickLower, tickUpper, swapData);
    }
}
