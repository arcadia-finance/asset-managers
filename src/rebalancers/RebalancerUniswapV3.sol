/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CollectParams, DecreaseLiquidityParams, IPositionManager, MintParams } from "./interfaces/IPositionManager.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IPool } from "./interfaces/IPool.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { Rebalancer } from "./Rebalancer.sol";
import { RebalanceParams } from "./libraries/RebalanceLogic2.sol";
import { PoolAddress } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { UniswapV3Logic } from "./libraries/uniswap-v3/UniswapV3Logic.sol";

/**
 * @title Rebalancer for Uniswap V3 Liquidity Positions.
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
contract RebalancerUniswapV3 is Rebalancer {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Uniswap v3 Position Manager.
    IPositionManager internal immutable POSITION_MANAGER;

    // The contract address of the Uniswap v3 Factory.
    address internal immutable UNISWAP_V3_FACTORY;

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
     * @param positionManager The contract address of the uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address uniswapV3Factory
    ) Rebalancer(arcadiaFactory, maxTolerance, maxInitiatorFee, minLiquidityRatio) {
        POSITION_MANAGER = IPositionManager(positionManager);
        UNISWAP_V3_FACTORY = uniswapV3Factory;
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the rebalancer.
     * @param positionManager the contract address of the position manager to check.
     */
    function isPositionManager(address positionManager) public view override returns (bool) {
        return positionManager == address(POSITION_MANAGER);
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
        // Positions have two underlying tokens.
        position.tokens = new address[](2);
        balances = new uint256[](2);

        // Rebalancer has withdrawn the underlying tokens from the Account.
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;

        // Get data of the Liquidity Position.
        (
            ,
            ,
            position.tokens[0],
            position.tokens[1],
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            ,
            ,
            ,
        ) = POSITION_MANAGER.positions(initiatorParams.oldId);

        // Get data of the Liquidity Pool.
        position.pool =
            PoolAddress.computeAddress(UNISWAP_V3_FACTORY, position.tokens[0], position.tokens[1], position.fee);
        position.id = initiatorParams.oldId;
        (position.sqrtPriceX96, position.tickCurrent,,,,,) = IUniswapV3Pool(position.pool).slot0();
        position.tickSpacing = IUniswapV3Pool(position.pool).tickSpacing();
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
        liquidity = IUniswapV3Pool(position.pool).liquidity();
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
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
    }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     */
    function _burn(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory
    ) internal override {
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
        bytes memory data = abi.encode(position.tokens[0], position.tokens[1], position.fee);

        // Do the swap.
        // Callback (external function) must be implemented in the main contract.
        (int256 deltaAmount0, int256 deltaAmount1) = IPool(position.pool).swap(
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
     * @notice Callback after executing a swap via IPool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the position.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the position.
     * @param data Any data passed by this contract via the IPool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Uniswap V3 or Slipstream position.
        (address token0, address token1, uint24 fee) = abi.decode(data, (address, address, uint24));

        if (UniswapV3Logic._computePoolAddress(token0, token1, fee) != msg.sender) revert OnlyPool();

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
     * @param position A struct with position and pool related variables.
     */
    function _mint(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory,
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
                fee: position.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: balances[0],
                amount1Desired: balances[1],
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        balances[0] = balances[0] - amount0;
        balances[1] = balances[1] - amount1;
    }
}
