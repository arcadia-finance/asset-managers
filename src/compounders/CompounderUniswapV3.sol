/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CollectParams, IncreaseLiquidityParams, IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";
import { Compounder } from "./Compounder.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Compounder for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the compounding functionality for a Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to compound the positions in their Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of compounding to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the compounding process,
 * ensuring that the execution remains within a controlled price range.
 */
contract CompounderUniswapV3 is Compounder {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Uniswap v3 Position Manager.
    IPositionManagerV3 internal immutable POSITION_MANAGER;

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
     * @param maxInitiatorFee The maximum initiator fee an initiator can set.
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        address positionManager,
        address uniswapV3Factory
    ) Compounder(arcadiaFactory, maxTolerance, maxInitiatorFee) {
        POSITION_MANAGER = IPositionManagerV3(positionManager);
        UNISWAP_V3_FACTORY = uniswapV3Factory;
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the compounder.
     * @param positionManager the contract address of the position manager to check.
     */
    function isPositionManager(address positionManager) public view override returns (bool) {
        return positionManager == address(POSITION_MANAGER);
    }

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the position and pool related state.
     * @param initiatorParams A struct with the initiator parameters.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(InitiatorParams memory initiatorParams)
        internal
        view
        override
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        position.tokens = new address[](2);
        (,, position.tokens[0], position.tokens[1], position.fee, position.tickLower, position.tickUpper,,,,,) =
            POSITION_MANAGER.positions(initiatorParams.id);

        // Get data of the Liquidity Pool.
        position.pool =
            PoolAddress.computeAddress(UNISWAP_V3_FACTORY, position.tokens[0], position.tokens[1], position.fee);
        (position.sqrtPrice,,,,,,) = IUniswapV3Pool(position.pool).slot0();
    }

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Compounder.
     * @param initiatorParams A struct with the initiator parameters.
     * param position A struct with position and pool related variables.
     * param cache A struct with cached variables.
     * @dev Must update the balances after the claim.
     */
    function _claim(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory,
        Cache memory
    ) internal override {
        (balances[0], balances[1]) = POSITION_MANAGER.collect(
            CollectParams({
                tokenId: initiatorParams.id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    /* ///////////////////////////////////////////////////////////////
                            SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Compounder.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    function _swapViaPool(
        uint256[] memory balances,
        Compounder.PositionState memory position,
        Compounder.Cache memory cache,
        bool zeroToOne,
        uint256 amountOut
    ) internal override {
        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 = uint160(zeroToOne ? cache.lowerBoundSqrtPrice : cache.upperBoundSqrtPrice);

        // Encode the swap data.
        bytes memory data = abi.encode(position.tokens[0], position.tokens[1], position.fee);

        // Do the swap.
        // Callback (external function) must be implemented in the main contract.
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check that pool is still balanced.
        // If sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received, the pool is not balanced anymore.
        // By setting the sqrtPrice to sqrtPriceLimitX96, the transaction will revert on the balance check.
        if (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0))) {
            position.sqrtPrice = sqrtPriceLimitX96;
        }

        // Update the balances.
        balances[0] = zeroToOne ? balances[0] - uint256(deltaAmount0) : balances[0] + uint256(-deltaAmount0);
        balances[1] = zeroToOne ? balances[1] + uint256(-deltaAmount1) : balances[1] - uint256(deltaAmount1);
    }

    /**
     * @notice Callback after executing a swap via IUniswapV3Pool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the position.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the position.
     * @param data Any data passed by this contract via the IUniswapV3Pool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Uniswap V3 Pool.
        (address token0, address token1, uint24 fee) = abi.decode(data, (address, address, uint24));

        if (PoolAddress.computeAddress(UNISWAP_V3_FACTORY, token0, token1, fee) != msg.sender) revert OnlyPool();

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Compounder.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * param cache A struct with cached variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal override {
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), amount0Desired);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), amount1Desired);
        (, uint256 amount0, uint256 amount1) = POSITION_MANAGER.increaseLiquidity(
            IncreaseLiquidityParams({
                tokenId: initiatorParams.id,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Update the balances.
        balances[0] -= amount0;
        balances[1] -= amount1;
    }
}
