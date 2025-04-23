/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceLogicExtension } from "../../../../utils/extensions/RebalanceLogicExtension.sol";
import { RebalancerUniV3Slipstream } from "../../../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";
import { stdError } from "../../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { SqrtPriceMath } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapLogic_Fuzz_Test } from "./_SwapLogic.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_swap" of contract "SwapLogic".
 */
contract Swap_SwapLogic_Fuzz_Test is SwapLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant INITIATOR_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RebalanceLogicExtension internal rebalanceLogic;
    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(SwapLogic_Fuzz_Test) {
        SwapLogic_Fuzz_Test.setUp();

        rebalanceLogic = new RebalanceLogicExtension();
        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swap_SwapViaRouter_ZeroAmountIn(
        bytes memory swapData,
        address positionManager,
        RebalancerUniV3Slipstream.PositionState memory position,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) public {
        // Given: AmountIn is zero.
        uint256 amountIn = 0;

        // When: Calling swap.
        (uint256 balance0_, uint256 balance1_,) = swapLogic.swap(
            swapData, positionManager, position, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
        );

        // Then: The correct balances are returned.
        assertEq(balance0_, balance0);
        assertEq(balance1_, balance1);
    }

    function testFuzz_Success_swap_SwapViaPool(
        uint128 liquidityPool,
        RebalancerUniV3Slipstream.PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1e3, UniswapHelpers.maxLiquidity(1) / 1e1));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;
        position.pool = address(poolUniswap);

        // And: An initial position.
        balance0 = uint64(bound(balance0, 1e6, type(uint64).max));
        balance1 = uint64(bound(balance1, 1e6, type(uint64).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: A new desired position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER / 1e2, BOUND_TICK_UPPER / 1e2 - 10));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 10, BOUND_TICK_UPPER / 1e2));
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // Get: the approximated swap parameters.
        (, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut) = rebalanceLogic
            .getRebalanceParams(
            1e18,
            POOL_FEE,
            INITIATOR_FEE,
            uint160(position.sqrtPriceX96),
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            balance0,
            balance1
        );

        // And: The pool is still balanced after the swap.
        position.lowerBoundSqrtPriceX96 = BOUND_SQRT_PRICE_LOWER;
        position.upperBoundSqrtPriceX96 = BOUND_SQRT_PRICE_UPPER;

        // When: Calling swapViaPool.
        (,, RebalancerUniV3Slipstream.PositionState memory position_) = swapLogic.swap(
            "",
            address(nonfungiblePositionManager),
            position,
            zeroToOne,
            amountInitiatorFee,
            amountIn,
            amountOut,
            balance0,
            balance1
        );

        // Then: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swap_SwapViaRouter_oneToZero(
        uint128 liquidityPool,
        RebalancerUniV3Slipstream.PositionState memory position,
        uint256 amountInitiatorFee,
        uint64 amountIn,
        uint64 amountOut,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swap.
        bytes memory swapData;
        {
            bytes memory data = abi.encodeWithSelector(
                RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
            );
            swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        }
        (uint256 balance0_, uint256 balance1_, RebalancerUniV3Slipstream.PositionState memory position_) = swapLogic
            .swap(
            swapData,
            address(nonfungiblePositionManager),
            position,
            true,
            amountInitiatorFee,
            amountIn,
            amountOut,
            balance0,
            balance1
        );

        // Then: The correct balances are returned.
        assertEq(balance0_, balance0 - amountIn);
        assertEq(balance1_, uint256(balance1) + amountOut);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swap_SwapViaRouter_ZeroToOne(
        uint128 liquidityPool,
        RebalancerUniV3Slipstream.PositionState memory position,
        uint256 amountInitiatorFee,
        uint64 amountIn,
        uint64 amountOut,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token0), address(routerMock), amountOut, true);

        // When: Calling swap.
        bytes memory swapData;
        {
            bytes memory data = abi.encodeWithSelector(
                RouterMock.swap.selector, address(token1), address(token0), uint128(amountIn), uint128(amountOut)
            );
            swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        }
        (uint256 balance0_, uint256 balance1_, RebalancerUniV3Slipstream.PositionState memory position_) = swapLogic
            .swap(
            swapData,
            address(nonfungiblePositionManager),
            position,
            false,
            amountInitiatorFee,
            amountIn,
            amountOut,
            balance0,
            balance1
        );

        // Then: The correct balances are returned.
        assertEq(balance0_, uint256(balance0) + amountOut);
        assertEq(balance1_, balance1 - amountIn);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }
}
