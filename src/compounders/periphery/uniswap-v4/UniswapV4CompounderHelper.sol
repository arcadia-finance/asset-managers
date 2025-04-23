/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { IPoolManager } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { IUniswapV4Compounder, PositionState, Fees } from "../../uniswap-v4/interfaces/IUniswapV4Compounder.sol";
import { LiquidityAmounts } from "../../libraries/LiquidityAmounts.sol";
import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    PositionInfo,
    PositionInfoLibrary
} from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { StateLibrary } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV4Logic } from "../../uniswap-v4/libraries/UniswapV4Logic.sol";

/**
 * @title Off-chain view functions for UniswapV4 Compounder Asset-Manager.
 * @author Pragma Labs
 * @notice This contract holds view functions accessible for initiators to check if the fees of a certain Liquidity Position can be compounded.
 */
contract UniswapV4CompounderHelper {
    using BalanceDeltaLibrary for BalanceDelta;
    using FixedPointMathLib for uint256;
    using StateLibrary for IPoolManager;
    /* //////////////////////////////////////////////////////////////
                            CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract addresse of the Asset Manager.
    IUniswapV4Compounder internal constant COMPOUNDER = IUniswapV4Compounder(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0);

    /* //////////////////////////////////////////////////////////////
                            ERRORS
    ////////////////////////////////////////////////////////////// */

    error QuoteSwap(uint128, uint160);
    error UnexpectedRevertBytes();
    error PoolManagerOnly();

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() { }

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @param account The address of the Arcadia Account.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @return compounder_ The address of the Compounder contract.
     * @return sqrtPriceX96 The current sqrtPriceX96 of the pool.
     */
    function isCompoundable(uint256 id, address account)
        public
        returns (bool isCompoundable_, address compounder_, uint160 sqrtPriceX96)
    {
        // Get current sqrtPriceX96 of the pool.
        (PoolKey memory poolKey, PositionInfo info) = UniswapV4Logic.POSITION_MANAGER.getPoolAndPositionInfo(id);
        (sqrtPriceX96,,,) = UniswapV4Logic.POOL_MANAGER.getSlot0(poolKey.toId());

        // Get the initiator.
        address initiator = COMPOUNDER.accountToInitiator(account);
        if (initiator == address(0)) return (false, address(0), 0);

        // Fetch and cache all position related data.
        PositionState memory position = COMPOUNDER.getPositionState(id, uint256(sqrtPriceX96), initiator);

        // It should never be unbalanced at this point as we fetch sqrtPriceX96 above.
        if (COMPOUNDER.isPoolUnbalanced(position)) return (false, address(0), 0);

        // Get fee amounts
        Fees memory balances;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(
                    address(UniswapV4Logic.POSITION_MANAGER), info.tickLower(), info.tickUpper(), bytes32(id)
                )
            );
            uint128 liquidity = UniswapV4Logic.POOL_MANAGER.getPositionLiquidity(poolKey.toId(), positionId);
            (balances.amount0, balances.amount1) = _getFeeAmounts(poolKey.toId(), info, liquidity, positionId);
        }

        // Remove initiator reward from fees, these will be send to the initiator.
        Fees memory desiredAmounts;
        (,, uint64 initiatorShare) = COMPOUNDER.initiatorInfo(initiator);
        desiredAmounts.amount0 = balances.amount0 - balances.amount0.mulDivDown(uint256(initiatorShare), 1e18);
        desiredAmounts.amount1 = balances.amount1 - balances.amount1.mulDivDown(uint256(initiatorShare), 1e18);

        // Calculate fee amounts to match ratios of current pool tick relative to ticks of the position.
        (bool zeroToOne, uint256 amountOut) = COMPOUNDER.getSwapParameters(position, desiredAmounts);
        (bool isPoolUnbalanced, uint256 amountIn) = _quote(poolKey, position, zeroToOne, amountOut);

        // Pool should still be balanced after the swap.
        if (isPoolUnbalanced) return (false, address(0), 0);

        // Calculate balances after swap.
        // Note that for the desiredAmounts only tokenOut is updated in UniswapV3Compounder,
        // but not tokenIn.
        if (zeroToOne) {
            desiredAmounts.amount1 += amountOut;
            balances.amount0 -= amountIn;
            balances.amount1 += amountOut;
        } else {
            desiredAmounts.amount0 += amountOut;
            balances.amount0 += amountOut;
            balances.amount1 -= amountIn;
        }

        // The balances of the fees after swapping must be bigger than the actual input amount when increasing liquidity.
        // Due to slippage, or for pools with high swapping fees this might not always hold.
        (uint256 amount0, uint256 amount1) = _getLiquidityAmounts(position, desiredAmounts);
        return (balances.amount0 > amount0 && balances.amount1 > amount1, address(COMPOUNDER), sqrtPriceX96);
    }

    /**
     * @notice Off-chain view function to get the quote of a swap.
     * @param poolKey The key containing information about the pool.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @return isPoolUnbalanced Bool indicating if the pool is unbalanced due to slippage after the swap.
     * @return amountIn The amount of tokenIn that is swapped to tokenOut.
     * @dev While this function does not persist state changes, it cannot be declared as view function,
     * since it uses a try - except pattern where it first does the swap (with state changes),
     * next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function _quote(PoolKey memory poolKey, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        returns (bool isPoolUnbalanced, uint256 amountIn)
    {
        // Don't get quote for swaps with zero amount.
        if (amountOut == 0) return (false, 0);

        // Max slippage: Pool should still be balanced after the swap.
        uint256 sqrtPriceLimitX96 = zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96;

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroToOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: uint160(sqrtPriceLimitX96)
        });

        bytes memory swapData = abi.encode(params, poolKey);
        uint160 sqrtPriceX96After;

        // This call should always revert with the simulated swap results (or other reason).
        try UniswapV4Logic.POOL_MANAGER.unlock(swapData) { }
        catch (bytes memory reason) {
            uint128 amountIn_;
            (amountIn_, sqrtPriceX96After) = _parseReason(reason);
            amountIn = uint256(amountIn_);
        }

        // Check if max slippage was exceeded (sqrtPriceLimitX96 is reached).
        isPoolUnbalanced = sqrtPriceX96After == sqrtPriceLimitX96 ? true : false;

        // Update the sqrtPriceX96 of the pool.
        position.sqrtPriceX96 = sqrtPriceX96After;
    }

    /**
     * @notice Parses revert data returned by a simulated Uniswap V4 swap.
     * @param reason The raw revert data returned by the simulated swap.
     * @return amountIn The input amount required for the swap.
     * @return sqrtPriceX96 The square root price after the simulated swap.
     */
    function _parseReason(bytes memory reason) internal pure returns (uint128 amountIn, uint160 sqrtPriceX96) {
        bytes4 selector;
        assembly {
            // Load the first 4 bytes of data (after the length prefix)
            selector := mload(add(reason, 0x20))
            amountIn := mload(add(reason, 0x24))
            sqrtPriceX96 := mload(add(reason, 0x44))
        }

        if (selector != QuoteSwap.selector) revert UnexpectedRevertBytes();
    }

    /**
     * @notice Executes a simulated swap and reverts with the amountIn and resulting sqrtPriceX96.
     * @dev This function is meant to be called during a swap simulation and intentionally reverts to return swap quote data.
     * @param data The encoded swap parameters and pool key.
     * @return results This function always reverts, so `results` is never returned
     */
    function unlockCallback(bytes calldata data) external payable returns (bytes memory) {
        if (msg.sender != address(UniswapV4Logic.POOL_MANAGER)) revert PoolManagerOnly();

        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));
        BalanceDelta swapDelta = IPoolManager(address(UniswapV4Logic.POOL_MANAGER)).swap(poolKey, params, "");

        // The input delta of a swap is negative so we must flip it.
        uint128 amountIn = params.zeroForOne ? uint128(-swapDelta.amount0()) : uint128(-swapDelta.amount1());
        (uint160 sqrtPriceX96,,,) = UniswapV4Logic.POOL_MANAGER.getSlot0(poolKey.toId());

        revert QuoteSwap(amountIn, sqrtPriceX96);
    }

    /**
     * @notice Retrieves the accumulated fee amounts of a Uniswap V4 position.
     * @param poolId The id of the pool that the position belongs to.
     * @param info The position information structure.
     * @param liquidity The amount of liquidity in the position.
     * @param positionId The id of the position used in UniswapV4 Position Manager.
     * @return amount0 The amount of token0 fees collected
     * @return amount1 The amount of token1 fees collected
     */
    function _getFeeAmounts(PoolId poolId, PositionInfo info, uint128 liquidity, bytes32 positionId)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            UniswapV4Logic.POOL_MANAGER.getFeeGrowthInside(poolId, info.tickLower(), info.tickUpper());

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            UniswapV4Logic.POOL_MANAGER.getPositionInfo(poolId, positionId);

        // Calculate accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in PositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 =
                FullMath.mulDiv(feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
            amount1 =
                FullMath.mulDiv(feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
        }
    }

    /**
     * @notice returns the actual amounts of token0 and token1 when increasing liquidity,
     * for a given position and desired amount of tokens.
     * @param position Struct with the position data.
     * @param amountsDesired Struct with the desired amounts of tokens supplied.
     * @return amount0 The actual amount of token0 supplied.
     * @return amount1 The actual amount of token1 supplied.
     */
    function _getLiquidityAmounts(PositionState memory position, Fees memory amountsDesired)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(position.sqrtPriceX96),
            uint160(position.sqrtRatioLower),
            uint160(position.sqrtRatioUpper),
            amountsDesired.amount0,
            amountsDesired.amount1
        );
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPriceX96),
            uint160(position.sqrtRatioLower),
            uint160(position.sqrtRatioUpper),
            liquidity
        );
    }
}
