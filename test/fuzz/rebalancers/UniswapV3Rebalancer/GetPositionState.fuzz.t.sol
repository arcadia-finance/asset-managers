/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "UniswapV3Rebalancer".
 */
contract GetPositionState_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState(InitVariables memory initVars, TestVariables memory testVars) public {
        // Given : Initialize a uniswapV3 pool
        bool token0HasLowestDecimals;
        uint256 initTokenId;
        (initVars, token0HasLowestDecimals, initTokenId) = initPool(initVars);

        // And : get valid position vars
        testVars = givenValidTestVars(testVars, initVars);

        // And : Create new position and generate fees
        uint256 tokenId = createNewPositionAndGenerateFees(testVars, uniV3Pool);

        /*         // When : Calling getPositionState()
        UniswapV3Rebalancer.PositionState memory position = rebalancer.getPositionState(tokenId);

        // Then : It should return the correct values
        assertEq(position.token0, address(token0));
        assertEq(position.token1, address(token1));
        assertEq(position.fee, POOL_FEE);
        assertEq(position.sqrtRatioLower, TickMath.getSqrtRatioAtTick(testVars.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(testVars.tickUpper));

        assertEq(position.pool, address(usdStablePool));

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = usdStablePool.slot0();

        int24 tickSpacing = (testVars.tickUpper - testVars.tickLower) / 2;
        int24 newUpperTick = currentTick + tickSpacing;
        int24 newLowerTick = currentTick - tickSpacing;
        assertEq(position.newUpperTick, newUpperTick);
        assertEq(position.newLowerTick, newLowerTick);

        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        uint256 priceToken0 = token0HasLowestDecimals ? 1e30 : 1e18;
        uint256 priceToken1 = token0HasLowestDecimals ? 1e18 : 1e30;

        uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
        uint256 lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(rebalancer.LOWER_SQRT_PRICE_DEVIATION(), 1e18);
        uint256 upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(rebalancer.UPPER_SQRT_PRICE_DEVIATION(), 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96); */
    }
}
