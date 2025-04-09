/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_mint" of contract "RebalancerUniswapV4".
 */
contract Mint_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniswapV4_Fuzz_Test) {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_mint(
        RebalancerUniswapV4.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);
        deal(position.token0, address(rebalancer), balance0, true);
        deal(position.token1, address(rebalancer), balance1, true);

        // Create pool.
        v4PoolKey = initializePoolV4(
            address(token0), address(token1), uint160(position.sqrtPriceX96), address(0), POOL_FEE, TICK_SPACING
        );
        position.fee = POOL_FEE;

        // When: Calling _mint().
        (uint256 id, uint256 liquidity) = rebalancer.mint(position, v4PoolKey, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(id), address(rebalancer));

        // And: Correct liquidity should be returned.
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            uint128 liquidity_ = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);
            assertEq(liquidity, liquidity_);
        }
    }

    function testFuzz_Success_mint_nativeETH(
        RebalancerUniswapV4.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        position.token0 = address(0);
        position.token1 = address(token1);
        vm.deal(address(rebalancer), balance0);
        deal(position.token1, address(rebalancer), balance1, true);

        // Create pool.
        nativeEthPoolKey = initializePoolV4(
            address(0), address(token1), uint160(position.sqrtPriceX96), address(0), POOL_FEE, TICK_SPACING
        );
        position.fee = POOL_FEE;

        // When: Calling _mint().
        (uint256 id, uint256 liquidity) = rebalancer.mint(position, nativeEthPoolKey, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(id), address(rebalancer));

        // And: Correct liquidity should be returned.
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            uint128 liquidity_ = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
            assertEq(liquidity, liquidity_);
        }
    }
}
