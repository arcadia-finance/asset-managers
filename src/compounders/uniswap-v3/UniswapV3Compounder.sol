/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { CollectParams, IncreaseLiquidityParams } from "./interfaces/INonfungiblePositionManager.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";

/**
 * @title Permissionless and Stateless Compounder for UniswapV3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the compounding functionality for a Uniswap V3 Liquidity Position in the Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The initiator will provide a trusted sqrtPriceX96 input at the time of compounding to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the compounding process,
 * ensuring that the execution remains within a controlled price range.
 */
contract UniswapV3Compounder is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // Minimum fees value in USD to trigger the compounding of a position, with 18 decimals precision.
    uint256 public immutable COMPOUND_THRESHOLD;
    // The share of the fees that are paid as reward to the initiator, with 18 decimals precision.
    uint256 public immutable INITIATOR_SHARE;
    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // relative to the sqrtPriceX96 calculated with trusted price feeds, with 18 decimals precision.
    uint256 public immutable LOWER_SQRT_PRICE_DEVIATION;
    // The maximum upper deviation of the pools actual sqrtPriceX96,
    // relative to the sqrtPriceX96 calculated with trusted price feeds, with 18 decimals precision.
    uint256 public immutable UPPER_SQRT_PRICE_DEVIATION;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to compound the fees for, used as transient storage.
    address internal account;

    // A struct with the state of a specific position, only used in memory.
    struct PositionState {
        address pool;
        address token0;
        address token1;
        uint24 fee;
        uint256 sqrtPriceX96;
        uint256 sqrtRatioLower;
        uint256 sqrtRatioUpper;
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
        uint256 usdPriceToken0;
        uint256 usdPriceToken1;
    }

    // A struct with variables to track the fee balances, only used in memory.
    struct Fees {
        uint256 amount0;
        uint256 amount1;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error BelowThreshold();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyPool();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Compound(address indexed account, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param compoundThreshold The minimum USD value that the compounded fees should have
     * before a compoundFees() can be called, with 18 decimals precision.
     * @param initiatorShare The share of the fees paid to the initiator as reward, with 18 decimals precision.
     * @param tolerance The maximum deviation of the actual pool price,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPriceX96 for the lower and upper boundaries.
     */
    constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance) {
        COMPOUND_THRESHOLD = compoundThreshold;
        INITIATOR_SHARE = initiatorShare;

        // SQRT_PRICE_DEVIATION is the square root of maximum/minimum price deviation.
        // Sqrt halves the number of decimals.
        LOWER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        UPPER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
    }

    /* ///////////////////////////////////////////////////////////////
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Compounds the fees earned by a UniswapV3 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the Liquidity Position.
     * @param trustedSqrtPriceX96 The pool sqrtPriceX96 provided at the time of calling compoundFees().
     */
    function compoundFees(address account_, uint256 id, uint256 trustedSqrtPriceX96) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeActionData(
            msg.sender, address(UniswapV3Logic.POSITION_MANAGER), id, trustedSqrtPriceX96
        );

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        emit Compound(account_, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param compoundData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return assetData A struct with the asset data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Verify that the pool's current price is initially within the defined tolerance price range.
     * - Collects the fees earned by the position.
     * - Verify that the fee value is bigger than the threshold required to trigger a compoundFees.
     * - Rebalance the fee amounts so that the maximum amount of liquidity can be added, swaps one token to another if needed.
     * - Verify that the pool's price is still within the defined tolerance price range after the swap.
     * - Increases the liquidity of the current position with those fees.
     * - Transfers a reward + dust amounts to the initiator.
     */
    function executeAction(bytes calldata compoundData) external override returns (ActionData memory assetData) {
        // Caller should be the Account, provided as input in compoundFees().
        if (msg.sender != account) revert OnlyAccount();

        // Decode compoundData.
        address initiator;
        uint256 trustedSqrtPriceX96;
        (assetData, initiator, trustedSqrtPriceX96) = abi.decode(compoundData, (ActionData, address, uint256));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        PositionState memory position = getPositionState(id, trustedSqrtPriceX96);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Collect fees.
        Fees memory fees;
        (fees.amount0, fees.amount1) = UniswapV3Logic.POSITION_MANAGER.collect(
            CollectParams({
                tokenId: id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Total value of the fees must be greater than the threshold.
        if (isBelowThreshold(position, fees)) revert BelowThreshold();

        // Subtract initiator reward from fees, these will be send to the initiator.
        fees.amount0 -= fees.amount0.mulDivDown(INITIATOR_SHARE, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(INITIATOR_SHARE, 1e18);

        // Rebalance the fee amounts so that the maximum amount of liquidity can be added.
        // The Pool must still be balanced after the swap.
        (bool zeroToOne, uint256 amountOut) = getSwapParameters(position, fees);
        if (_swap(position, zeroToOne, amountOut)) revert UnbalancedPool();

        // We increase the fee amount of tokenOut, but we do not decrease the fee amount of tokenIn.
        // This guarantees that tokenOut is the limiting factor when increasing liquidity and not tokenIn.
        // As a consequence, slippage will result in less tokenIn going to the initiator,
        // instead of more tokenOut going to the initiator.
        if (zeroToOne) fees.amount1 += amountOut;
        else fees.amount0 += amountOut;

        // Increase liquidity of the position.
        // The approval for at least one token after increasing liquidity will remain non-zero.
        // We have to set approval first to 0 for ERC20 tokens that require the approval to be set to zero
        // before setting it to a non-zero value.
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), fees.amount0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), fees.amount1);
        UniswapV3Logic.POSITION_MANAGER.increaseLiquidity(
            IncreaseLiquidityParams({
                tokenId: id,
                amount0Desired: fees.amount0,
                amount1Desired: fees.amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Initiator rewards are transferred to the initiator.
        uint256 balance0 = ERC20(position.token0).balanceOf(address(this));
        uint256 balance1 = ERC20(position.token1).balanceOf(address(this));
        if (balance0 > 0) ERC20(position.token0).safeTransfer(initiator, balance0);
        if (balance1 > 0) ERC20(position.token1).safeTransfer(initiator, balance1);

        // Approve Account to deposit Liquidity Position back into the Account.
        UniswapV3Logic.POSITION_MANAGER.approve(msg.sender, id);
    }

    /* ///////////////////////////////////////////////////////////////
                        SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice returns the swap parameters to optimize the total value of fees that can be added as liquidity.
     * @param position Struct with the position data.
     * @param fees Struct with the fee balances.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountOut The amount of tokenOut.
     * @dev We assume the fees amount are small compared to the liquidity of the pool,
     * hence we neglect slippage when optimizing the swap amounts.
     * Slippage must be limited, the contract enforces that the pool is still balanced after the swap and
     * since we use swaps with amountOut, slippage will result in less reward of tokenIn for the initiator,
     * not less liquidity increased.
     */
    function getSwapParameters(PositionState memory position, Fees memory fees)
        public
        pure
        returns (bool zeroToOne, uint256 amountOut)
    {
        if (position.sqrtPriceX96 >= position.sqrtRatioUpper) {
            // Position is out of range and fully in token 1.
            // Swap full amount of token0 to token1.
            zeroToOne = true;
            amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
        } else if (position.sqrtPriceX96 <= position.sqrtRatioLower) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            zeroToOne = false;
            amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, fees.amount1);
        } else {
            // Position is in range.
            // Rebalance fees so that the ratio of the fee values matches with ratio of the position.
            uint256 targetRatio =
                UniswapV3Logic._getTargetRatio(position.sqrtPriceX96, position.sqrtRatioLower, position.sqrtRatioUpper);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
            uint256 totalFeeValueInToken1 = fees.amount1 + fee0ValueInToken1;
            uint256 currentRatio = fees.amount1.mulDivDown(1e18, totalFeeValueInToken1);

            if (currentRatio < targetRatio) {
                // Swap token0 partially to token1.
                zeroToOne = true;
                amountOut = (targetRatio - currentRatio).mulDivDown(totalFeeValueInToken1, 1e18);
            } else {
                // Swap token1 partially to token0.
                zeroToOne = false;
                uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalFeeValueInToken1, 1e18);
                amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amountIn);
            }
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V3 Pool of the Liquidity Position.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced due to slippage of the swap.
     */
    function _swap(PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        returns (bool isPoolUnbalanced_)
    {
        // Don't do swaps with zero amount.
        if (amountOut == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Do the swap.
        bytes memory data = abi.encode(position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        isPoolUnbalanced_ = (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0)));
    }

    /**
     * @notice Callback after executing a swap via IUniswapV3Pool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the pool.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the pool.
     * @param data Any data passed by this contract via the IUniswapV3Pool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Uniswap V3 pool.
        (address token0, address token1, uint24 fee) = abi.decode(data, (address, address, uint24));
        if (UniswapV3Logic._computePoolAddress(token0, token1, fee) != msg.sender) revert OnlyPool();

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    POSITION AND POOL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @param trustedSqrtPriceX96 The pool sqrtPriceX96 provided at the time of calling compoundFees().
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id, uint256 trustedSqrtPriceX96)
        public
        view
        virtual
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        int24 tickLower;
        int24 tickUpper;
        (,, position.token0, position.token1, position.fee, tickLower, tickUpper,,,,,) =
            UniswapV3Logic.POSITION_MANAGER.positions(id);
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (position.usdPriceToken0, position.usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Get data of the Liquidity Pool.
        position.pool = UniswapV3Logic._computePoolAddress(position.token0, position.token1, position.fee);
        (position.sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        position.lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(LOWER_SQRT_PRICE_DEVIATION, 1e18);
        position.upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(UPPER_SQRT_PRICE_DEVIATION, 1e18);
    }

    /**
     * @notice Returns if the total fee value in USD is below the rebalancing threshold.
     * @param position Struct with the position data.
     * @param fees Struct with the fees accumulated by a position.
     * @return isBelowThreshold_ Bool indicating if the total fee value in USD is below the threshold.
     */
    function isBelowThreshold(PositionState memory position, Fees memory fees)
        public
        view
        virtual
        returns (bool isBelowThreshold_)
    {
        uint256 totalValueFees = position.usdPriceToken0.mulDivDown(fees.amount0, 1e18)
            + position.usdPriceToken1.mulDivDown(fees.amount1, 1e18);

        isBelowThreshold_ = totalValueFees < COMPOUND_THRESHOLD;
    }

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ = position.sqrtPriceX96 < position.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 > position.upperBoundSqrtPriceX96;
    }

    /* ///////////////////////////////////////////////////////////////
                      ERC721 HANDLER FUNCTION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the onERC721Received selector.
     * @dev Required to receive ERC721 tokens via safeTransferFrom.
     */
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
