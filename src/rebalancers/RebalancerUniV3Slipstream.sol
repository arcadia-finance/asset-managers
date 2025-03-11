/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { BurnLogic } from "./libraries/shared-uniswap-v3-slipstream/BurnLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FeeLogic } from "./libraries/FeeLogic.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IStrategyHook } from "./interfaces/IStrategyHook.sol";
import { MintLogic } from "./libraries/shared-uniswap-v3-slipstream/MintLogic.sol";
import { PricingLogic } from "./libraries/cl-math/PricingLogic.sol";
import { RebalanceLogic } from "./libraries/RebalanceLogic.sol";
import { SafeApprove } from "./libraries/SafeApprove.sol";
import { SlipstreamLogic } from "./libraries/slipstream/SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./libraries/slipstream/StakedSlipstreamLogic.sol";
import { SwapLogic } from "./libraries/shared-uniswap-v3-slipstream/SwapLogic.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV3Logic } from "./libraries/uniswap-v3/UniswapV3Logic.sol";

/**
 * @title Rebalancing logic for Uniswap V3 and Slipstream Liquidity Positions.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
contract RebalancerUniV3Slipstream {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // A struct with the state of a specific position, only used in memory.
    struct PositionState {
        address pool;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        int24 tickUpper;
        int24 tickLower;
        uint128 liquidity;
        uint160 sqrtRatioLower;
        uint160 sqrtRatioUpper;
        uint256 sqrtPriceX96;
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InsufficientLiquidity();
    error OnlyPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator, address indexed strategyHook);
    event Rebalance(address indexed account, address indexed positionManager, uint256 oldId, uint256 newId);

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() { }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param rebalanceData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @param hook The address of the strategy hook, if any.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function rebalance(bytes calldata rebalanceData, address hook) external returns (ActionData memory depositData) {
        // Decode rebalanceData.
        bytes memory swapData;
        address positionManager;
        uint256 oldId;
        uint256 newId;
        PositionState memory position;
        address initiator;
        {
            ActionData memory assetData;
            int24 tickLower;
            int24 tickUpper;
            (assetData, initiator, tickLower, tickUpper, swapData) =
                abi.decode(rebalanceData, (ActionData, address, int24, int24, bytes));
            positionManager = assetData.assets[0];
            oldId = assetData.assetIds[0];

            // Fetch and cache all position related data.
            position = getPositionState(positionManager, oldId, tickLower, tickUpper, initiator);
        }

        // If set, call the strategy hook before the rebalance (view function).
        // This can be used to enforce additional constraints on the rebalance, specific to the Account/Id.
        // Such as:
        // - Directional preferences.
        // - Minimum Cool Down Periods.
        // - Excluding rebalancing of certain positions.
        // - ...
        if (hook != address(0)) {
            IStrategyHook(hook).beforeRebalance(
                msg.sender, positionManager, oldId, position.tickLower, position.tickUpper
            );
        }

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Remove liquidity of the position and claim outstanding fees/rewards.
        (uint256 balance0, uint256 balance1, uint256 reward) = BurnLogic._burn(positionManager, oldId, position);

        {
            // Get the rebalance parameters.
            // These are calculated based on a hypothetical swap through the pool, without slippage.
            (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut) =
            RebalanceLogic._getRebalanceParams(
                initiatorInfo[initiator].minLiquidityRatio,
                position.fee,
                initiatorInfo[initiator].fee,
                position.sqrtPriceX96,
                position.sqrtRatioLower,
                position.sqrtRatioUpper,
                balance0,
                balance1
            );

            // Do the actual swap to rebalance the position.
            // This can be done either directly through the pool, or via a router with custom swap data.
            // For swaps directly through the pool, if slippage is bigger than calculated, the transaction will not immediately revert,
            // but excess slippage will be subtracted from the initiatorFee.
            // For swaps via a router, tokenOut should be the limiting factor when increasing liquidity.
            (balance0, balance1) = SwapLogic._swap(
                swapData,
                positionManager,
                position,
                zeroToOne,
                amountInitiatorFee,
                amountIn,
                amountOut,
                balance0,
                balance1
            );

            // Check that the pool is still balanced after the swap.
            if (isPoolUnbalanced(position)) revert UnbalancedPool();

            // Mint the new liquidity position.
            // We mint with the total available balances of token0 and token1, not subtracting the initiator fee.
            // Leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
            // and the initiator fee will be 0 (but the transaction will not revert).
            uint256 liquidity;
            (newId, liquidity, balance0, balance1) = MintLogic._mint(positionManager, position, balance0, balance1);

            // Check that the actual liquidity of the position is above the minimum threshold.
            // This prevents loss of principal of the liquidity position due to slippage,
            // or malicious initiators who remove liquidity during a custom swap.
            if (liquidity < minLiquidity) revert InsufficientLiquidity();

            // Transfer fee to the initiator.
            (balance0, balance1) = FeeLogic._transfer(
                initiator, zeroToOne, amountInitiatorFee, position.token0, position.token1, balance0, balance1
            );
        }

        // Approve Account to redeposit Liquidity Position and leftovers.
        {
            uint256 count = 1;
            IPositionManager(positionManager).approve(msg.sender, newId);
            if (balance0 > 0) {
                ERC20(position.token0).safeApproveWithRetry(msg.sender, balance0);
                count = 2;
            }
            if (balance1 > 0) {
                ERC20(position.token1).safeApproveWithRetry(msg.sender, balance1);
                ++count;
            }
            if (reward > 0) {
                ERC20(StakedSlipstreamLogic.REWARD_TOKEN).safeApproveWithRetry(msg.sender, reward);
                ++count;
            }

            // Encode deposit data for the flash-action.
            depositData =
                ArcadiaLogic._encodeDeposit(positionManager, newId, position, count, balance0, balance1, reward);
        }

        // If set, call the strategy hook after the rebalance (non view function).
        // Can be used to check additional constraints and persist state changes on the hook.
        if (hook != address(0)) IStrategyHook(hook).afterRebalance(msg.sender, positionManager, oldId, newId);

        return depositData;
    }

    /* ///////////////////////////////////////////////////////////////
                    PUBLIC POSITION VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ = position.sqrtPriceX96 <= position.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 >= position.upperBoundSqrtPriceX96;
    }

    /**
     * @notice Fetches all required position data from external contracts.
     * @param positionManager The contract address of the Position Manager.
     * @param oldId The oldId of the Liquidity Position.
     * @param tickLower The lower tick of the newly minted position.
     * @param tickUpper The upper tick of the newly minted position.
     * @param initiator The address of the initiator.
     * @return position Struct with the position data.
     */
    function getPositionState(
        address positionManager,
        uint256 oldId,
        int24 tickLower,
        int24 tickUpper,
        address initiator
    ) public view virtual returns (PositionState memory position) {
        // Get data of the Liquidity Position.
        (int24 tickCurrent, int24 tickRange) = positionManager == address(UniswapV3Logic.POSITION_MANAGER)
            ? UniswapV3Logic._getPositionState(position, oldId, tickLower == tickUpper)
            // Logic holds for both Slipstream and staked Slipstream positions.
            : SlipstreamLogic._getPositionState(position, oldId);

        // Store the new ticks for the rebalance
        if (tickLower == tickUpper) {
            // Round current tick down to a tick that is a multiple of the tick spacing (can be initialised).
            // We do not handle the edge cases where the new ticks might exceed MIN_TICK or MAX_TICK.
            // This will result in a revert during the mint, if ever needed a different rebalancer has to be deployed.
            tickCurrent = tickCurrent / position.tickSpacing * position.tickSpacing;
            // For tick ranges that are an even multiple of the tick spacing, we use a symmetric spacing around the current tick.
            // For uneven multiples, the smaller part is below the current tick.
            position.tickLower = tickCurrent - tickRange / (2 * position.tickSpacing) * position.tickSpacing;
            position.tickUpper = position.tickLower + tickRange;
        } else {
            (position.tickLower, position.tickUpper) = (tickLower, tickUpper);
        }
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (uint256 usdPriceToken0, uint256 usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        // We do not handle the edge cases where exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        position.lowerBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        position.upperBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
    }
}
