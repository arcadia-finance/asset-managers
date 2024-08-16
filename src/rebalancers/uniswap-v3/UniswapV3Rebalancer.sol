/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../../libraries/ArcadiaLogic.sol";
import {
    CollectParams,
    DecreaseLiquidityParams,
    MintParams
} from "../../interfaces/uniswap-v3/INonfungiblePositionManager.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "../../interfaces/IAccount.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "../../libraries/LiquidityAmounts.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Logic } from "../../libraries/UniswapV3Logic.sol";

/**
 * @title Permissioned rebalancer for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice
 * @dev
 */
contract UniswapV3Rebalancer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // TODO The max fees that are paid as reward to the initiator, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;
    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // relative to the sqrtPriceX96 calculated with trusted price feeds, with 18 decimals precision.
    uint256 public immutable LOWER_SQRT_PRICE_DEVIATION;
    // The maximum upper deviation of the pools actual sqrtPriceX96,
    // relative to the sqrtPriceX96 calculated with trusted price feeds, with 18 decimals precision.
    uint256 public immutable UPPER_SQRT_PRICE_DEVIATION;
    uint256 public immutable LIQUIDITY_TRESHOLD;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to compound the fees for, used as transient storage.
    address internal account;

    // A mapping that sets an initiator per position of an owner.
    // An initiator is approved by the owner to rebalance its specified uniswapV3 position.
    mapping(address owner => mapping(uint256 positionId => address initiator)) public ownerToIdToInitiator;

    // A mapping from initiator to rebalancing fee.
    mapping(address initiator => uint256 fee) public initiatorFee;

    // A struct with the state of a specific position, only used in memory.
    struct PositionState {
        address pool;
        address token0;
        address token1;
        uint24 fee;
        int24 newUpperTick;
        int24 newLowerTick;
        uint128 liquidity;
        uint256 sqrtPriceX96;
        uint256 sqrtRatioLower;
        uint256 sqrtRatioUpper;
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error FeeAlreadySet();
    error LiquidityTresholdExceeded();
    error MaxInitiatorFee();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyPool();
    error Reentered();
    error UnbalancedPool();
    error InitiatorNotValid();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Rebalance(address indexed account, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param tolerance The maximum deviation of the actual pool price,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param liquidityTreshold .
     */
    constructor(uint256 tolerance, uint256 liquidityTreshold) {
        // SQRT_PRICE_DEVIATION is the square root of maximum/minimum price deviation.
        // Sqrt halves the number of decimals.
        LOWER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        UPPER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);

        // TODO: max treshold ?
        LIQUIDITY_TRESHOLD = liquidityTreshold;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the Liquidity Position.
     */
    function rebalancePosition(address account_, uint256 id) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        if (ownerToIdToInitiator[IAccount(account_).owner()][id] != msg.sender) revert InitiatorNotValid();

        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData =
            ArcadiaLogic._encodeActionData(msg.sender, address(UniswapV3Logic.POSITION_MANAGER), id);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit Rebalance(account_, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param rebalanceData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return assetData A struct with the asset data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     */
    function executeAction(bytes calldata rebalanceData) external override returns (ActionData memory assetData) {
        // Cache account
        address account_ = account;
        // Caller should be the Account, provided as input in rebalancePosition().
        if (msg.sender != account_) revert OnlyAccount();

        // Decode rebalanceData.
        address initiator;
        (assetData, initiator) = abi.decode(rebalanceData, (ActionData, address));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        PositionState memory position = getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        {
            uint256 totalLiquidity = uint256(IUniswapV3Pool(position.pool).liquidity());
            uint256 maxLiquidity = totalLiquidity.mulDivDown(LIQUIDITY_TRESHOLD, 1e18);
            if (position.liquidity > maxLiquidity) revert LiquidityTresholdExceeded();
        }

        // Rebalance the position so that the maximum liquidity can be added at 50/50 ration around current price.
        // Use same tick spacing for rebalancing.
        // The Pool must still be balanced after the swap.
        (bool zeroToOne, uint256 amountOut) = getSwapParameters(position, id);
        if (_swap(position, zeroToOne, amountOut)) revert UnbalancedPool();

        // Increase liquidity of the position.
        // The approval for at least one token after increasing liquidity will remain non-zero.
        // We have to set approval first to 0 for ERC20 tokens that require the approval to be set to zero
        // before setting it to a non-zero value.
        uint256 balance0 = ERC20(position.token0).balanceOf(address(this));
        uint256 balance1 = ERC20(position.token1).balanceOf(address(this));
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), balance0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), balance1);

        (uint256 newTokenId,, uint256 amount0, uint256 amount1) = UniswapV3Logic.POSITION_MANAGER.mint(
            MintParams({
                token0: position.token0,
                token1: position.token1,
                fee: position.fee,
                tickLower: position.newLowerTick,
                tickUpper: position.newUpperTick,
                amount0Desired: balance0,
                amount1Desired: balance1,
                amount0Min: 0,
                amount1Min: 0,
                // TODO: send direct to actionHandler ?
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Update the tokenId for newly minted position
        assetData.assetIds[0] = newTokenId;

        // Any surplus is transferred to the Account.
        balance0 -= amount0;
        balance1 -= amount1;
        if (balance0 > 0) ERC20(position.token0).safeTransfer(account_, balance0);
        if (balance1 > 0) ERC20(position.token1).safeTransfer(account_, balance1);

        // Approve ActionHandler to deposit Liquidity Position back into the Account.
        UniswapV3Logic.POSITION_MANAGER.approve(msg.sender, newTokenId);
    }

    /* ///////////////////////////////////////////////////////////////
                        INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    function setInitiatorForPosition(address initiator, uint256 tokenId) external {
        ownerToIdToInitiator[msg.sender][tokenId] = initiator;
    }

    function setInitiatorFee(uint24 fee) external {
        if (initiatorFee[msg.sender] > 0) revert FeeAlreadySet();
        if (fee > MAX_INITIATOR_FEE) revert MaxInitiatorFee();
        initiatorFee[msg.sender] = fee;
    }

    /* ///////////////////////////////////////////////////////////////
                        SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice returns the swap parameters to optimize the total value of fees that can be added as liquidity.
     * @param position Struct with the position data.
     * @param id St
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountOut The amount of tokenOut.
     * @dev We assume the fees amount are small compared to the liquidity of the pool,
     * hence we neglect slippage when optimizing the swap amounts.
     * Slippage must be limited, the contract enforces that the pool is still balanced after the swap and
     * since we use swaps with amountOut, slippage will result in less reward of tokenIn for the initiator,
     * not less liquidity increased.
     */
    function getSwapParameters(PositionState memory position, uint256 id)
        public
        returns (bool zeroToOne, uint256 amountOut)
    {
        // Remove liquidity of the position and claim outstanding fees to get full amounts of token0 and token1
        // for rebalance.
        UniswapV3Logic.POSITION_MANAGER.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: id,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        (uint256 amount0, uint256 amount1) = UniswapV3Logic.POSITION_MANAGER.collect(
            CollectParams({
                tokenId: id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Burn the position
        UniswapV3Logic.POSITION_MANAGER.burn(id);

        // Get target ratio in token1 terms
        uint256 targetRatio = UniswapV3Logic._getTargetRatio(
            position.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.newLowerTick),
            TickMath.getSqrtRatioAtTick(position.newUpperTick)
        );

        // Calculate the total fee value in token1 equivalent:
        uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
        uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
        uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

        if (currentRatio < targetRatio) {
            // Swap token0 partially to token1.
            zeroToOne = true;
            amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, 1e18);
        } else {
            // Swap token1 partially to token0.
            zeroToOne = false;
            uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, 1e18);
            amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amountIn);
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
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id) public view returns (PositionState memory position) {
        // Get data of the Liquidity Position.
        int24 tickLower;
        int24 tickUpper;
        (,, position.token0, position.token1, position.fee, tickLower, tickUpper, position.liquidity,,,,) =
            UniswapV3Logic.POSITION_MANAGER.positions(id);
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (uint256 usdPriceToken0, uint256 usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Get data of the Liquidity Pool.
        position.pool = UniswapV3Logic._computePoolAddress(position.token0, position.token1, position.fee);
        int24 currentTick;
        (position.sqrtPriceX96, currentTick,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Store the new ticks for the rebalance
        // TODO: validate if ok to divide by 2 for uneven numbers
        int24 tickSpacing = (tickUpper - tickLower) / 2;
        position.newUpperTick = currentTick + tickSpacing;
        position.newLowerTick = currentTick - tickSpacing;

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        position.lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(LOWER_SQRT_PRICE_DEVIATION, 1e18);
        position.upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(UPPER_SQRT_PRICE_DEVIATION, 1e18);
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
