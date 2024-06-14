/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { FixedPoint96 } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPoint128 } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { ICLPool } from "../interfaces/Slipstream/ICLPool.sol";
import { ISlipstreamPositionManager } from "../interfaces/Slipstream/ISlipstreamPositionManager.sol";
import { PoolAddress } from "../../../lib/accounts-v2/src/asset-modules/Slipstream/libraries/PoolAddress.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

library SlipstreamLogic {
    using FixedPointMathLib for uint256;

    // The binary precision of sqrtPriceX96 squared.
    uint256 internal constant Q192 = FixedPoint96.Q96 ** 2;

    // The Slipstream Factory contract.
    address internal constant CL_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;

    // The Slipstream NonfungiblePositionManager contract.
    ISlipstreamPositionManager internal constant POSITION_MANAGER =
        ISlipstreamPositionManager(0x827922686190790b37229fd06084350E74485b72);

    /**
     * @notice Computes the contract address of a Slipstream Pool.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param tickSpacing The tick spacing of the Pool.
     * @return pool The contract address of the Slipstream Pool.
     */
    function _computePoolAddress(address token0, address token1, int24 tickSpacing)
        internal
        view
        returns (address pool)
    {
        pool = PoolAddress.computeAddress(CL_FACTORY, token0, token1, tickSpacing);
    }

    /**
     * @notice Calculates the amountOut for a given amountIn and sqrtPriceX96 for a hypothetical
     * swap without slippage.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount that of tokenIn that must be swapped to tokenOut.
     * @return amountOut The amount of tokenOut.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different auto compounder has to be deployed
     * that does two consecutive mulDivs.
     */
    function _getAmountOut(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountIn)
        internal
        pure
        returns (uint256 amountOut)
    {
        amountOut = zeroToOne
            ? FullMath.mulDiv(amountIn, sqrtPriceX96 ** 2, Q192)
            : FullMath.mulDiv(amountIn, Q192, sqrtPriceX96 ** 2);
    }

    /**
     * @notice Calculates the sqrtPriceX96 (token1/token0) from trusted USD prices of both tokens.
     * @param priceToken0 The price of 1e18 tokens of token0 in USD, with 18 decimals precision.
     * @param priceToken1 The price of 1e18 tokens of token1 in USD, with 18 decimals precision.
     * @return sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @dev The price in Uniswap V3 is defined as:
     * price = amountToken1/amountToken0.
     * The usdPriceToken is defined as: usdPriceToken = amountUsd/amountToken.
     * => amountToken = amountUsd/usdPriceToken.
     * Hence we can derive the Uniswap V3 price as:
     * price = (amountUsd/usdPriceToken1)/(amountUsd/usdPriceToken0) = usdPriceToken0/usdPriceToken1.
     */
    function _getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) internal pure returns (uint160 sqrtPriceX96) {
        if (priceToken1 == 0) return TickMath.MAX_SQRT_RATIO;

        // Both priceTokens have 18 decimals precision and result of division should have 28 decimals precision.
        // -> multiply by 1e28
        // priceXd28 will overflow if priceToken0 is greater than 1.158e+49.
        // For WBTC (which only has 8 decimals) this would require a bitcoin price greater than 115 792 089 237 316 198 989 824 USD/BTC.
        uint256 priceXd28 = priceToken0.mulDivDown(1e28, priceToken1);
        // Square root of a number with 28 decimals precision has 14 decimals precision.
        uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);

        // Change sqrtPrice from a decimal fixed point number with 14 digits to a binary fixed point number with 96 digits.
        // Unsafe cast: Cast will only overflow when priceToken0/priceToken1 >= 2^128.
        sqrtPriceX96 = uint160((sqrtPriceXd14 << FixedPoint96.RESOLUTION) / 1e14);
    }
}
