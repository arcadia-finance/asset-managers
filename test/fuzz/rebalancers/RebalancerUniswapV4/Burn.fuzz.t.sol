/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_burn" of contract "RebalancerUniswapV4".
 */
contract Burn_BurnLogic_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniswapV4_Fuzz_Test) {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_burn(
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        FeeGrowth memory feeData
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        uint256 id =
            initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        {
            bytes32 positionId =
                keccak256(abi.encodePacked(address(positionManagerV4), BOUND_TICK_LOWER, BOUND_TICK_UPPER, bytes32(id)));
            position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

            (uint160 sqrtPrice,,,) = stateView.getSlot0(v4PoolKey.toId());

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(BOUND_TICK_LOWER),
                TickMath.getSqrtPriceAtTick(BOUND_TICK_UPPER),
                position.liquidity
            );
            // Ensure a minimum amount of both tokens in the position
            vm.assume(amount0 > 1e6 && amount1 > 1e6);
        }

        // And : Set fees for pool in general (amount below are defined in USD)
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, 100);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, 100);
        uint128 liquidity = stateView.getLiquidity(v4PoolKey.toId());
        feeData = setFeeState(feeData, v4PoolKey, liquidity);

        // And: Position has accumulated fees.
        (uint256 feeAmount0, uint256 feeAmount1) =
            getFeeAmounts(id, v4PoolKey.toId(), BOUND_TICK_LOWER, BOUND_TICK_UPPER, position.liquidity);
        vm.assume(feeAmount0 + feeAmount1 > 0);

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());
        (uint256 principal0, uint256 principal1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(BOUND_TICK_LOWER),
            TickMath.getSqrtPriceAtTick(BOUND_TICK_UPPER),
            position.liquidity
        );

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // When: Calling _burn().
        rebalancer.burn(id, address(token0), address(token1));

        // Then: Correct balances should be returned.
        assertEq(token0.balanceOf(address(rebalancer)), principal0 + feeAmount0);
        assertEq(token1.balanceOf(address(rebalancer)), principal1 + feeAmount1);
    }

    function testFuzz_Success_burn_nativeETH(uint128 liquidity) public {
        // Given: A valid position.
        liquidity = uint128(bound(liquidity, 1, UniswapHelpers.maxLiquidity(1)));
        (uint256 id, uint256 sqrtPriceX96) = deployNativeEthPool(liquidity, POOL_FEE, TICK_SPACING, address(0));

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), BOUND_TICK_LOWER, BOUND_TICK_UPPER, bytes32(id)));
        liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(sqrtPriceX96),
            TickMath.getSqrtPriceAtTick(BOUND_TICK_LOWER),
            TickMath.getSqrtPriceAtTick(BOUND_TICK_UPPER),
            liquidity
        );

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        assertEq(address(rebalancer).balance, 0);
        assertEq(token1.balanceOf(address(rebalancer)), 0);

        // When: Calling _burn().
        rebalancer.burn(id, address(0), address(token1));

        // Then: Assets should have been sent to the rebalancer.
        assertEq(address(rebalancer).balance, amount0);
        assertEq(token1.balanceOf(address(rebalancer)), amount1);
    }
}
