/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Logic_Fuzz_Test } from "./_UniswapV3Logic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "UniswapV3Logic".
 */
contract GetPositionState_UniswapV3Logic_Fuzz_Test is UniswapV3Logic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(UniswapV3Logic_Fuzz_Test) {
        UniswapV3Logic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_NoTickSpacing(Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Tokens are deployed.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);

        // Create pool and position.
        IUniswapV3PoolExtension pool =
            createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(position.sqrtPriceX96), 300);
        (uint256 id,,) = addLiquidityUniV3(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // When: Calling _getPositionState().
        int24 tickCurrent;
        int24 tickRange;
        Rebalancer.PositionState memory positionActual;
        (tickCurrent, tickRange, positionActual) = uniswapV3Logic.getPositionState(positionActual, id, false);

        // Then: It should return the correct values.
        assertEq(tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)));
        assertEq(tickRange, position.tickUpper - position.tickLower);

        // And: positionActual is updated.
        assertEq(positionActual.token0, address(token0));
        assertEq(positionActual.token1, address(token1));
        assertEq(positionActual.fee, POOL_FEE);
        assertEq(positionActual.liquidity, position.liquidity);
        assertEq(positionActual.pool, address(pool));
        assertEq(positionActual.sqrtPriceX96, position.sqrtPriceX96);
        assertEq(positionActual.tickSpacing, 0);
    }

    function testFuzz_Success_getPositionState_WithTickSpacing(Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Tokens are deployed.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);

        // Create pool and position.
        IUniswapV3PoolExtension pool =
            createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(position.sqrtPriceX96), 300);
        (uint256 id,,) = addLiquidityUniV3(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // When: Calling _getPositionState().
        int24 tickCurrent;
        int24 tickRange;
        Rebalancer.PositionState memory positionActual;
        (tickCurrent, tickRange, positionActual) = uniswapV3Logic.getPositionState(positionActual, id, true);

        // Then: It should return the correct values.
        assertEq(tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)));
        assertEq(tickRange, position.tickUpper - position.tickLower);

        // And: positionActual is updated.
        assertEq(positionActual.token0, address(token0));
        assertEq(positionActual.token1, address(token1));
        assertEq(positionActual.fee, POOL_FEE);
        assertEq(positionActual.liquidity, position.liquidity);
        assertEq(positionActual.pool, address(pool));
        assertEq(positionActual.sqrtPriceX96, position.sqrtPriceX96);
        assertEq(positionActual.tickSpacing, 1);
    }
}
