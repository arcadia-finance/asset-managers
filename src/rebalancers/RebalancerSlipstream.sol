/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import {
    CollectParams, DecreaseLiquidityParams, ICLPositionManager, MintParams
} from "./interfaces/ICLPositionManager.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ICLPool } from "./interfaces/ICLPool.sol";
import { IStakedSlipstream } from "./interfaces/IStakedSlipstream.sol";
import { SlipstreamLogic } from "../libraries/SlipstreamLogic.sol";
import { Rebalancer } from "./Rebalancer.sol";
import { RebalanceParams } from "./libraries/RebalanceLogic.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Rebalancer for Slipstream Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permisionned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPriceX96 input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
contract RebalancerSlipstream is Rebalancer {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Slipstream Factory.
    address internal immutable CL_FACTORY;

    // The contract address of the Slipstream Position Manager.
    ICLPositionManager internal immutable POSITION_MANAGER;

    // The contract address of the Slipstream Pool Implementation.
    address internal immutable POOL_IMPLEMENTATION;

    // The contract address of the Reward Token (Aero).
    address internal immutable REWARD_TOKEN;

    // The contract address of the Staked Slipstream Asset Module.
    address internal immutable STAKED_SLIPSTREAM_AM;

    // The contract address of the Staked Slipstream Wrapper.
    address internal immutable STAKED_SLIPSTREAM_WRAPPER;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error OnlyPool();

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum fee an initiator can set,
     * relative to the ideal amountIn, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param positionManager The contract address of the Slipstream Position Manager.
     * @param cLFactory The contract address of the Slipstream Factory.
     * @param poolImplementation The contract address of the Slipstream Pool Implementation.
     * @param rewardToken The contract address of the Reward Token (Aero).
     * @param stakedSlipstreamAm The contract address of the Staked Slipstream Asset Module.
     * @param stakedSlipstreamWrapper The contract address of the Staked Slipstream Wrapper.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    ) Rebalancer(arcadiaFactory, maxTolerance, maxInitiatorFee, minLiquidityRatio) {
        POSITION_MANAGER = ICLPositionManager(positionManager);
        CL_FACTORY = cLFactory;
        POOL_IMPLEMENTATION = poolImplementation;
        REWARD_TOKEN = rewardToken;
        STAKED_SLIPSTREAM_AM = stakedSlipstreamAm;
        STAKED_SLIPSTREAM_WRAPPER = stakedSlipstreamWrapper;
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the rebalancer.
     * @param positionManager the contract address of the position manager to check.
     */
    function isPositionManager(address positionManager) public view override returns (bool) {
        return (
            positionManager == address(STAKED_SLIPSTREAM_AM) || positionManager == address(STAKED_SLIPSTREAM_WRAPPER)
                || positionManager == address(POSITION_MANAGER)
        );
    }

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the underlying assets of the pool.
     * @param initiatorParams A struct with the initiator parameters.
     * @return token0 The contract address of token0.
     * @return token1 The contract address of token1.
     */
    function _getUnderlyingTokens(InitiatorParams memory initiatorParams)
        internal
        view
        override
        returns (address token0, address token1)
    {
        (,, token0, token1,,,,,,,,) = POSITION_MANAGER.positions(initiatorParams.oldId);
    }

    /**
     * @notice Returns the position and pool related state.
     * @param initiatorParams A struct with the initiator parameters.
     * @return balances The balances of the underlying tokens of the position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(InitiatorParams memory initiatorParams)
        internal
        view
        override
        returns (uint256[] memory balances, PositionState memory position)
    {
        // Get data of the Liquidity Position.
        address token0;
        address token1;
        (,, token0, token1, position.tickSpacing, position.tickLower, position.tickUpper, position.liquidity,,,,) =
            POSITION_MANAGER.positions(initiatorParams.oldId);

        // If it is a non staked position, or the position is staked and the reward token is the same as one of the underlying tokens,
        // there are two underlying assets, otherwise there are three.
        if (
            initiatorParams.positionManager == address(POSITION_MANAGER) || token0 == REWARD_TOKEN
                || token1 == REWARD_TOKEN
        ) {
            // Positions have two underlying tokens.
            balances = new uint256[](2);
            position.tokens = new address[](2);
        } else {
            // Positions have three underlying tokens.
            balances = new uint256[](3);
            position.tokens = new address[](3);
            position.tokens[2] = REWARD_TOKEN;
        }
        position.tokens[0] = token0;
        position.tokens[1] = token1;

        // Rebalancer has withdrawn the underlying tokens from the Account.
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;

        // Get data of the Liquidity Pool.
        position.pool = SlipstreamLogic.computeAddress(
            POOL_IMPLEMENTATION, CL_FACTORY, position.tokens[0], position.tokens[1], position.tickSpacing
        );
        position.id = initiatorParams.oldId;
        (position.sqrtPriceX96, position.tickCurrent,,,,) = ICLPool(position.pool).slot0();
        position.fee = ICLPool(position.pool).fee();
    }

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(Rebalancer.PositionState memory position)
        internal
        view
        override
        returns (uint128 liquidity)
    {
        liquidity = ICLPool(position.pool).liquidity();
    }

    /**
     * @notice Returns the sqrtPriceX96 of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPriceX96 The sqrtPriceX96 of the Pool.
     */
    function _getSqrtPriceX96(Rebalancer.PositionState memory position)
        internal
        view
        override
        returns (uint160 sqrtPriceX96)
    {
        (sqrtPriceX96,,,,,) = ICLPool(position.pool).slot0();
    }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     */
    function _burn(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory
    ) internal override {
        // If position is a staked slipstream position, first unstake the position.
        if (initiatorParams.positionManager != address(POSITION_MANAGER)) {
            // If rewardToken is an underlying token of the position, add it to the balances
            uint256 rewards = IStakedSlipstream(initiatorParams.positionManager).burn(position.id);
            if (balances.length == 3) balances[2] = rewards;
            else if (position.tokens[0] == REWARD_TOKEN) balances[0] += rewards;
            else balances[1] += rewards;
        }

        // Remove liquidity of the position and claim outstanding fees to get full amounts of token0 and token1
        // for rebalance.
        POSITION_MANAGER.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: position.id,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // We assume that the amount of tokens to collect never exceeds type(uint128).max.
        (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(
            CollectParams({
                tokenId: position.id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        balances[0] += amount0;
        balances[1] += amount1;

        // Burn the position
        POSITION_MANAGER.burn(position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param rebalanceParams A struct with the rebalance parameters.
     * @param cache A struct with cached variables.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    function _swapViaPool(
        uint256[] memory balances,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint256 amountOut
    ) internal override {
        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(rebalanceParams.zeroToOne ? cache.lowerBoundSqrtPriceX96 : cache.upperBoundSqrtPriceX96);

        // Encode the swap data.
        bytes memory data = abi.encode(position.tokens[0], position.tokens[1], position.tickSpacing);

        // Do the swap.
        // Callback (external function) must be implemented in the main contract.
        (int256 deltaAmount0, int256 deltaAmount1) = ICLPool(position.pool).swap(
            address(this), rebalanceParams.zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data
        );

        // Check that pool is still balanced.
        // If sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received, the pool is not balanced anymore.
        // By setting the sqrtPriceX96 to sqrtPriceLimitX96, the transaction will revert on the balance check.
        if (amountOut > (rebalanceParams.zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0))) {
            position.sqrtPriceX96 = sqrtPriceLimitX96;
        }

        // Update the balances.
        balances[0] =
            rebalanceParams.zeroToOne ? balances[0] - uint256(deltaAmount0) : balances[0] + uint256(-deltaAmount0);
        balances[1] =
            rebalanceParams.zeroToOne ? balances[1] + uint256(-deltaAmount1) : balances[1] - uint256(deltaAmount1);
    }

    /**
     * @notice Callback after executing a swap via ICLPool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the position.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the position.
     * @param data Any data passed by this contract via the ICLPool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Slipstream Pool.
        (address token0, address token1, int24 tickSpacing) = abi.decode(data, (address, address, int24));

        if (SlipstreamLogic.computeAddress(POOL_IMPLEMENTATION, CL_FACTORY, token0, token1, tickSpacing) != msg.sender)
        {
            revert OnlyPool();
        }

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     */
    function _mint(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory
    ) internal override {
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), balances[0]);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), balances[1]);

        uint256 amount0;
        uint256 amount1;
        (position.id, position.liquidity, amount0, amount1) = POSITION_MANAGER.mint(
            MintParams({
                token0: position.tokens[0],
                token1: position.tokens[1],
                tickSpacing: position.tickSpacing,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: balances[0],
                amount1Desired: balances[1],
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        );

        balances[0] = balances[0] - amount0;
        balances[1] = balances[1] - amount1;

        // If position is a staked slipstream position, stake the position.
        if (initiatorParams.positionManager != address(POSITION_MANAGER)) {
            POSITION_MANAGER.approve(initiatorParams.positionManager, position.id);
            IStakedSlipstream(initiatorParams.positionManager).mint(position.id);
        }
    }
}
