/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AbstractBase } from "./AbstractBase.sol";
import {
    CollectParams,
    DecreaseLiquidityParams,
    IncreaseLiquidityParams,
    ICLPositionManager,
    MintParams
} from "../rebalancers/interfaces/ICLPositionManager.sol";
import { CLMath } from "../libraries/CLMath.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { ICLPool } from "../rebalancers/interfaces/ICLPool.sol";
import { IStakedSlipstream } from "../rebalancers/interfaces/IStakedSlipstream.sol";
import { PositionState } from "../state/PositionState.sol";
import { SlipstreamLogic } from "../libraries/SlipstreamLogic.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Base implementation for managing Slipstream Liquidity Positions.
 */
abstract contract Slipstream is AbstractBase {
    using FixedPointMathLib for uint256;
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
     * @param positionManager The contract address of the Slipstream Position Manager.
     * @param cLFactory The contract address of the Slipstream Factory.
     * @param poolImplementation The contract address of the Slipstream Pool Implementation.
     * @param rewardToken The contract address of the Reward Token (Aero).
     * @param stakedSlipstreamAm The contract address of the Staked Slipstream Asset Module.
     * @param stakedSlipstreamWrapper The contract address of the Staked Slipstream Wrapper.
     */
    constructor(
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    ) {
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
    function isPositionManager(address positionManager) public view virtual override returns (bool) {
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
     * param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return token0 The contract address of token0.
     * @return token1 The contract address of token1.
     */
    function _getUnderlyingTokens(address, uint256 id)
        internal
        view
        virtual
        override
        returns (address token0, address token1)
    {
        (,, token0, token1,,,,,,,,) = POSITION_MANAGER.positions(id);
    }

    /**
     * @notice Returns the position and pool related state.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(address positionManager, uint256 id)
        internal
        view
        virtual
        override
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        position.id = id;
        address token0;
        address token1;
        (,, token0, token1, position.tickSpacing, position.tickLower, position.tickUpper, position.liquidity,,,,) =
            POSITION_MANAGER.positions(id);

        // If it is a non staked position, or the position is staked and the reward token is the same as one of the underlying tokens,
        // there are two underlying assets, otherwise there are three.
        if (positionManager == address(POSITION_MANAGER) || token0 == REWARD_TOKEN || token1 == REWARD_TOKEN) {
            // Positions have two underlying tokens.
            position.tokens = new address[](2);
        } else {
            // Positions have three underlying tokens.
            position.tokens = new address[](3);
            position.tokens[2] = REWARD_TOKEN;
        }
        position.tokens[0] = token0;
        position.tokens[1] = token1;

        // Get data of the Liquidity Pool.
        position.pool =
            SlipstreamLogic.computeAddress(POOL_IMPLEMENTATION, CL_FACTORY, token0, token1, position.tickSpacing);
        (position.sqrtPrice, position.tickCurrent,,,,) = ICLPool(position.pool).slot0();
        position.fee = ICLPool(position.pool).fee();
    }

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(PositionState memory position)
        internal
        view
        virtual
        override
        returns (uint128 liquidity)
    {
        liquidity = ICLPool(position.pool).liquidity();
    }

    /**
     * @notice Returns the sqrtPrice of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPrice The sqrtPrice of the Pool.
     */
    function _getSqrtPrice(PositionState memory position) internal view virtual override returns (uint160 sqrtPrice) {
        (sqrtPrice,,,,,) = ICLPool(position.pool).slot0();
    }

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param claimFee The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     */
    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) internal virtual override {
        if (positionManager != address(POSITION_MANAGER)) {
            // If position is a staked slipstream position, claim the rewards.
            uint256 rewards = IStakedSlipstream(positionManager).claimReward(position.id);
            if (rewards > 0) {
                uint256 fee = rewards.mulDivDown(claimFee, 1e18);
                if (balances.length == 3) {
                    (balances[2], fees[2]) = (balances[2] + rewards, fees[2] + fee);
                }
                // If rewardToken is an underlying token of the position, add it to the balances
                else if (position.tokens[0] == REWARD_TOKEN) {
                    (balances[0], fees[0]) = (balances[0] + rewards, fees[0] + fee);
                } else {
                    (balances[1], fees[1]) = (balances[1] + rewards, fees[1] + fee);
                }
            }
        } else {
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

            // Calculate claim fees.
            fees[0] += amount0.mulDivDown(claimFee, 1e18);
            fees[1] += amount1.mulDivDown(claimFee, 1e18);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                          UNSTAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Unstakes a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        virtual
        override
    {
        // If position is a staked slipstream position, unstake the position.
        if (positionManager != address(POSITION_MANAGER)) {
            uint256 rewards = IStakedSlipstream(positionManager).burn(position.id);
            if (rewards > 0) {
                if (balances.length == 3) balances[2] = rewards;
                // If rewardToken is an underlying token of the position, add it to the balances
                else if (position.tokens[0] == REWARD_TOKEN) balances[0] += rewards;
                else balances[1] += rewards;
            }
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _burn(uint256[] memory balances, address, PositionState memory position) internal virtual override {
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
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        virtual
        override
    {
        // Do the swap.
        (int256 deltaAmount0, int256 deltaAmount1) = ICLPool(position.pool).swap(
            address(this),
            zeroToOne,
            -int256(amountOut),
            zeroToOne ? CLMath.MIN_SQRT_PRICE_LIMIT : CLMath.MAX_SQRT_PRICE_LIMIT,
            abi.encode(position.tokens[0], position.tokens[1], position.tickSpacing)
        );

        // Update the balances.
        balances[0] = zeroToOne ? balances[0] - uint256(deltaAmount0) : balances[0] + uint256(-deltaAmount0);
        balances[1] = zeroToOne ? balances[1] + uint256(-deltaAmount1) : balances[1] - uint256(deltaAmount1);
    }

    /**
     * @notice Callback after executing a swap via ICLPool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the position.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the position.
     * @param data Any data passed by this contract via the ICLPool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external virtual {
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
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to mint as liquidity.
     * @param amount1Desired The desired amount of token1 to mint as liquidity.
     */
    function _mint(
        uint256[] memory balances,
        address,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual override {
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), amount0Desired);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), amount1Desired);

        uint256 amount0;
        uint256 amount1;
        (position.id, position.liquidity, amount0, amount1) = POSITION_MANAGER.mint(
            MintParams({
                token0: position.tokens[0],
                token1: position.tokens[1],
                tickSpacing: position.tickSpacing,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPrice: 0
            })
        );

        balances[0] -= amount0;
        balances[1] -= amount1;
    }

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        address,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual override {
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), amount0Desired);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), amount1Desired);

        uint256 amount0;
        uint256 amount1;
        (position.liquidity, amount0, amount1) = POSITION_MANAGER.increaseLiquidity(
            IncreaseLiquidityParams({
                tokenId: position.id,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        balances[0] -= amount0;
        balances[1] -= amount1;
    }

    /* ///////////////////////////////////////////////////////////////
                          STAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Stakes a Liquidity Position.
     * param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _stake(uint256[] memory, address positionManager, PositionState memory position)
        internal
        virtual
        override
    {
        // If position is a staked slipstream position, stake the position.
        if (positionManager != address(POSITION_MANAGER)) {
            POSITION_MANAGER.approve(positionManager, position.id);
            IStakedSlipstream(positionManager).mint(position.id);
        }
    }
}
