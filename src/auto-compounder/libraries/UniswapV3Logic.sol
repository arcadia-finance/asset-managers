/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { FixedPoint96 } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPoint128 } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { INonfungiblePositionManager } from "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import { PoolAddress } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

library UniswapV3Logic {
    using FixedPointMathLib for uint256;

    // The binary precision of sqrtPriceX96 squared.
    uint256 internal constant Q192 = FixedPoint96.Q96 ** 2;

    // The Uniswap V3 Factory contract.
    address internal constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // The Uniswap V3 NonfungiblePositionManager contract.
    INonfungiblePositionManager internal constant POSITION_MANAGER =
        INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);

    /**
     * @notice Calculates the underlying token amounts of accrued fees, both collected and uncollected.
     * @param id The id of the Liquidity Position.
     * @return amount0 The amount of fees in underlying token0 tokens.
     * @return amount1 The amount of fees in underlying token1 tokens.
     */
    function _getFeeAmounts(uint256 id) internal view returns (uint256 amount0, uint256 amount1) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint256 liquidity, // gas: cheaper to use uint256 instead of uint128.
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0, // gas: cheaper to use uint256 instead of uint128.
            uint256 tokensOwed1 // gas: cheaper to use uint256 instead of uint128.
        ) = POSITION_MANAGER.positions(id);

        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            _getFeeGrowthInside(token0, token1, fee, tickLower, tickUpper);

        // Calculate the total amount of fees by adding the already realized fees (tokensOwed),
        // to the accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in NonfungiblePositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 = FullMath.mulDiv(
                feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed0;
            amount1 = FullMath.mulDiv(
                feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed1;
        }
    }

    /**
     * @notice Calculates the current fee growth inside the Liquidity Range.
     * @param token0 Token0 of the Liquidity Pool.
     * @param token1 Token1 of the Liquidity Pool.
     * @param fee The fee of the Liquidity Pool.
     * @param tickLower The lower tick of the liquidity position.
     * @param tickUpper The upper tick of the liquidity position.
     * @return feeGrowthInside0X128 The amount of fees in underlying token0 tokens.
     * @return feeGrowthInside1X128 The amount of fees in underlying token1 tokens.
     */
    function _getFeeGrowthInside(address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(UNISWAP_V3_FACTORY, token0, token1, fee));

        // To calculate the pending fees, the current tick has to be used, even if the pool would be unbalanced.
        (, int24 tickCurrent,,,,,) = pool.slot0();
        (,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,) = pool.ticks(tickLower);
        (,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,) = pool.ticks(tickUpper);

        // Calculate the fee growth inside of the Liquidity Range since the last time the position was updated.
        // feeGrowthInside can overflow (without reverting), as is the case in the Uniswap fee calculations.
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                feeGrowthInside0X128 =
                    pool.feeGrowthGlobal0X128() - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    pool.feeGrowthGlobal1X128() - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
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
