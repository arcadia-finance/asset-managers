/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { SlipstreamLogic_Fuzz_Test } from "./_SlipstreamLogic.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "SlipstreamLogic".
 */
contract GetPositionState_SlipstreamLogic_Fuzz_Test is SlipstreamLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    int24 internal constant TICK_SPACING = 1;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(SlipstreamLogic_Fuzz_Test) {
        SlipstreamLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState(Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(TICK_SPACING)));

        // And: Tokens are deployed.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);

        // Create pool and position.
        ICLPoolExtension pool =
            createPoolCL(address(token0), address(token1), TICK_SPACING, uint160(position.sqrtPriceX96), 300);
        (uint256 id,,) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // When: Calling _getPositionState().
        int24 tickCurrent;
        int24 tickRange;
        Rebalancer.PositionState memory positionActual;
        (tickCurrent, tickRange, positionActual) = slipstreamLogic.getPositionState(positionActual, id);

        // Then: It should return the correct values.
        assertEq(tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)));
        assertEq(tickRange, position.tickUpper - position.tickLower);

        // And: positionActual is updated.
        assertEq(positionActual.token0, address(token0));
        assertEq(positionActual.token1, address(token1));
        assertEq(positionActual.tickSpacing, TICK_SPACING);
        assertEq(positionActual.liquidity, position.liquidity);
        assertEq(positionActual.pool, address(pool));
        assertEq(positionActual.sqrtPriceX96, position.sqrtPriceX96);
        assertEq(positionActual.fee, pool.fee());
    }
}
