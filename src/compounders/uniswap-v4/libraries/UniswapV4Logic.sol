/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { IPoolManager } from "../interfaces/IPoolManager.sol";
import { IPositionManager } from "../interfaces/IPositionManager.sol";
import { IStateView } from "../interfaces/IStateView.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

library UniswapV4Logic {
    using BalanceDeltaLibrary for BalanceDelta;
    using FixedPointMathLib for uint256;

    // The binary precision of sqrtPriceX96 squared.
    uint256 internal constant Q192 = FixedPoint96.Q96 ** 2;

    // Actions used by the Uniswap V4 PositionManager.
    uint256 internal constant INCREASE_LIQUIDITY = 0x00;
    uint256 internal constant DECREASE_LIQUIDITY = 0x01;
    uint256 internal constant SETTLE_PAIR = 0x0d;
    uint256 internal constant TAKE_PAIR = 0x11;

    // The Uniswap V4 PoolManager contract.
    IPoolManager internal constant POOL_MANAGER = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
    // The Uniswap V4 PositionManager contract.
    IPositionManager internal constant POSITION_MANAGER = IPositionManager(0x7C5f5A4bBd8fD63184577525326123B519429bDc);
    // The Uniswap V4 StateView contract.
    // TODO: Check why getSlot0 fails (StateLibrary not implemented on PoolManager).
    IStateView internal constant STATE_VIEW = IStateView(0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71);

    /**
     * @notice Calculates the amountOut for a given amountIn and sqrtPriceX96 for a hypothetical
     * swap without slippage.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount that of tokenIn that must be swapped to tokenOut.
     * @return amountOut The amount of tokenOut.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different auto compounder has to be deployed,
     * which does two consecutive mulDivs.
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
     * @dev The price in Uniswap V3 and V4 is defined as:
     * price = amountToken1/amountToken0.
     * The usdPriceToken is defined as: usdPriceToken = amountUsd/amountToken.
     * => amountToken = amountUsd/usdPriceToken.
     * Hence we can derive the Uniswap V3 and V4 price as:
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

    /**
     * @notice Calculates the ratio of how much of the total value of a liquidity position has to be provided in token1.
     * @param sqrtPriceX96 The square root of the current pool price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position.
     * @return targetRatio The ratio of the value of token1 compared to the total value of the position, with 18 decimals precision.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different auto compounder has to be deployed,
     * which does two consecutive mulDivs.
     * @dev Derivation of the formula:
     * 1) The ratio is defined as:
     *    R = valueToken1 / (valueToken0 + valueToken1)
     *    If we express all values in token1 en use the current pool price to denominate token0 in token1:
     *    R = amount1 / (amount0 * sqrtPrice² + amount1)
     * 2) Amount0 for a given liquidity position of a Uniswap V3 and V4 pool is given as:
     *    Amount0 = liquidity * (sqrtRatioUpper - sqrtPrice) / (sqrtRatioUpper * sqrtPrice)
     * 3) Amount1 for a given liquidity position of a Uniswap V3 and V4 pool is given as:
     *    Amount1 = liquidity * (sqrtPrice - sqrtRatioLower)
     * 4) Combining 1), 2) and 3) and simplifying we get:
     *    R = [sqrtPrice - sqrtRatioLower] / [2 * sqrtPrice - sqrtRatioLower - sqrtPrice² / sqrtRatioUpper]
     */
    function _getTargetRatio(uint256 sqrtPriceX96, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        internal
        pure
        returns (uint256 targetRatio)
    {
        uint256 numerator = sqrtPriceX96 - sqrtRatioLower;
        uint256 denominator = 2 * sqrtPriceX96 - sqrtRatioLower - sqrtPriceX96 ** 2 / sqrtRatioUpper;

        targetRatio = numerator.mulDivDown(1e18, denominator);
    }

    /**
     * @notice Processes token balance changes resulting from a swap operation
     * @dev Handles token transfers between the contract and the Pool Manager based on delta values:
     *      - For tokens owed to the Pool Manager: transfers tokens and calls settle()
     *      - For tokens owed from the Pool Manager: calls take() to receive tokens
     * @param delta The BalanceDelta containing the positive/negative changes in token amounts
     * @param currency0 The address of the first token in the pair
     * @param currency1 The address of the second token in the pair
     */
    function _processSwapDelta(BalanceDelta delta, Currency currency0, Currency currency1) internal {
        if (delta.amount0() < 0) {
            POOL_MANAGER.sync(currency0);
            currency0.transfer(address(POOL_MANAGER), uint128(-delta.amount0()));
            POOL_MANAGER.settle();
        }
        if (delta.amount1() < 0) {
            POOL_MANAGER.sync(currency1);
            currency1.transfer(address(POOL_MANAGER), uint128(-delta.amount1()));
            POOL_MANAGER.settle();
        }

        if (delta.amount0() > 0) {
            POOL_MANAGER.take(currency0, (address(this)), uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            POOL_MANAGER.take(currency1, address(this), uint128(delta.amount1()));
        }
    }
}
