/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";
import { UniswapV4Logic } from "../../../../src/compounders/uniswap-v4/libraries/UniswapV4Logic.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "UniswapV4Compounder".
 */
contract GetPositionState_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState(TestVariables memory testVars) public {
        // Given : Valid State
        bool token0HasLowestDecimals;
        (testVars, token0HasLowestDecimals) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // When : Calling getPositionState()
        (UniswapV4Compounder.PositionState memory position, PoolKey memory poolKey) =
            compounder.getPositionState(tokenId);

        // Then : It should return the correct values
        assertEq(position.sqrtRatioLower, TickMath.getSqrtRatioAtTick(testVars.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(testVars.tickUpper));

        uint256 priceToken0 = token0HasLowestDecimals ? 1e30 : 1e18;
        uint256 priceToken1 = token0HasLowestDecimals ? 1e18 : 1e30;

        assertEq(position.usdPriceToken0, priceToken0);
        assertEq(position.usdPriceToken1, priceToken1);

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(stablePoolKey.toId());

        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        uint256 trustedSqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(priceToken0, priceToken1);
        uint256 lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(compounder.LOWER_SQRT_PRICE_DEVIATION(), 1e18);
        uint256 upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(compounder.UPPER_SQRT_PRICE_DEVIATION(), 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96);

        assertEq(PoolId.unwrap(poolKey.toId()), PoolId.unwrap(stablePoolKey.toId()));
    }
}
