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
 * @notice The Rebalancer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Uniswap V3 Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setInitiatorForAccount() that will be permisionned to rebalance
 * all UniswapV3 Liquidity Positions held in that Account.
 *   @dev The contract prevents frontrunning/sandwiching by comparing the actual pool price with a pool price calculated from trusted
 * price feeds (oracles). The tolerance in terms of price deviation is specific to the initiator but limited by a global MAX_TOLERANCE.
 * Some oracles can however deviate from the actual price by a few percent points, this could potentially open attack vectors by manipulating
 * pools and sandwiching the swap and/or increase liquidity. This asset manager should not be used for Arcadia Account that have/will have
 * Uniswap V3 Liquidity Positions where one of the underlying assets is priced with such low precision oracles.
 */
contract UniswapV3Rebalancer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // The maximum deviation of the actual pool price, in % with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // TODO
    uint256 public immutable MAX_INITIATOR_FEE = 0.01 * 1e18;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to compound the fees for, used as transient storage.
    address internal account;

    // A mapping that sets an initiator per position of an owner.
    // An initiator is approved by the owner to rebalance its specified uniswapV3 position.
    mapping(address owner => mapping(address account => address initiator)) public ownerToAccountToInitiator;

    // A mapping from initiator to rebalancing fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

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
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
    }

    // A struct used to store information for each specific initiator
    struct InitiatorInfo {
        uint256 upperSqrtPriceDeviation;
        uint256 lowerSqrtPriceDeviation;
        uint256 fee;
        bool initialized;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error DecreaseFeeOnly();
    error DecreaseToleranceOnly();
    error FeeAlreadySet();
    error LiquidityTresholdExceeded();
    error MaxInitiatorFee();
    error MaxTolerance();
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
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     */
    constructor(uint256 maxTolerance) {
        MAX_TOLERANCE = maxTolerance;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Rebalances a UniswapV3 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the Liquidity Position to rebalance.
     * @param lowerTick The new lower tick to rebalance to.
     * @param upperTick The new upper tick to rebalance to.
     * @dev When both lowerTick and upperTick are zero, ticks will be updated with same tick-spacing as current position
     * and with a balanced, 50/50 ratio around current tick.
     */
    function rebalancePosition(address account_, uint256 id, int24 lowerTick, int24 upperTick) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        if (ownerToAccountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InitiatorNotValid();

        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeActionDataRebalancer(
            msg.sender, address(UniswapV3Logic.POSITION_MANAGER), id, lowerTick, upperTick
        );

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
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata rebalanceData) external override returns (ActionData memory assetData) {
        // Cache account
        address account_ = account;
        // Caller should be the Account, provided as input in rebalancePosition().
        if (msg.sender != account_) revert OnlyAccount();

        // Decode rebalanceData.
        address initiator;
        int24 lowerTick;
        int24 upperTick;
        (assetData, initiator, lowerTick, upperTick) = abi.decode(rebalanceData, (ActionData, address, int24, int24));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        PositionState memory position = getPositionState(id, lowerTick, upperTick, initiator);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

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

        // Rebalance the position so that the maximum liquidity can be added for new ticks.
        // The Pool must still be balanced after the swap.
        (bool zeroToOne, uint256 amountIn) = getSwapParameters(position, amount0, amount1);
        if (_swap(position, zeroToOne, amountIn)) revert UnbalancedPool();

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

        uint256 newTokenId;
        (newTokenId,, amount0, amount1) = UniswapV3Logic.POSITION_MANAGER.mint(
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
    /**
     * @notice Sets an initiator for an Account. An initiator will be permisionned to rebalance any UniswapV3
     * Liquidity Position held in the specified Arcadia Account.
     * @param initiator The address of the initiator.
     * @param account_ The address of the Arcadia Account to set an initiator for.
     */
    function setInitiatorForAccount(address initiator, address account_) external {
        ownerToAccountToInitiator[msg.sender][account_] = initiator;
    }

    /**
     * @notice Sets the information requested for an initiator.
     * @param fee . TODO
     * @param tolerance The maximum deviation of the actual pool price,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPriceX96 for the lower and upper boundaries.
     */
    function setInitiatorInfo(uint256 tolerance, uint256 fee) external {
        // Cache struct
        InitiatorInfo memory initiatorInfo_ = initiatorInfo[msg.sender];

        if (initiatorInfo_.initialized == true && fee > initiatorInfo_.fee) revert DecreaseFeeOnly();
        if (fee > MAX_INITIATOR_FEE) revert MaxInitiatorFee();
        if (tolerance > MAX_TOLERANCE) revert MaxTolerance();

        initiatorInfo_.fee = fee;

        // SQRT_PRICE_DEVIATION is the square root of maximum/minimum price deviation.
        // Sqrt halves the number of decimals.
        uint256 upperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        if (initiatorInfo_.initialized == true && upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation) {
            revert DecreaseToleranceOnly();
        }

        initiatorInfo_.lowerSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        initiatorInfo_.upperSqrtPriceDeviation = upperSqrtPriceDeviation;

        // Set initiator as initialized if it wasn't already.
        if (initiatorInfo_.initialized == false) initiatorInfo_.initialized = true;

        initiatorInfo[msg.sender] = initiatorInfo_;
    }

    /* ///////////////////////////////////////////////////////////////
                        SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the swap parameters to optimize the total value that can be added as liquidity.
     * @param position Struct with the position data.
     * @param amount0 The amount of token0 that is available for the rebalance.
     * @param amount1 The amount of token1 that is available for the rebalance.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountIn The amount of tokenIn.
     * @dev Slippage must be limited, the contract enforces that the pool is still balanced after the swap.
     */
    function getSwapParameters(PositionState memory position, uint256 amount0, uint256 amount1)
        public
        pure
        returns (bool zeroToOne, uint256 amountIn)
    {
        uint256 sqrtRatioUpperTick = TickMath.getSqrtRatioAtTick(position.newUpperTick);
        uint256 sqrtRatioLowerTick = TickMath.getSqrtRatioAtTick(position.newLowerTick);

        if (position.sqrtPriceX96 >= sqrtRatioUpperTick) {
            // Position is out of range and fully in token 1.
            // Swap full amount of token0 to token1.
            zeroToOne = true;
            amountIn = amount0;
        } else if (position.sqrtPriceX96 <= sqrtRatioLowerTick) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            amountIn = amount1;
        } else {
            // Get target ratio in token1 terms.
            uint256 targetRatio =
                UniswapV3Logic._getTargetRatio(position.sqrtPriceX96, sqrtRatioLowerTick, sqrtRatioUpperTick);

            // Calculate the total fee value in token1 equivalent:
            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            // Cache fee to avoid stack too deep.
            uint24 fee = position.fee;

            if (currentRatio < targetRatio) {
                // Swap token0 partially to token1.
                zeroToOne = true;
                uint256 denominator = 1e18 + targetRatio.mulDivDown(fee, 1e6 - fee);
                uint256 amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, denominator);
                // convert to amountIn
                amountIn = UniswapV3Logic._getAmountIn(position.sqrtPriceX96, zeroToOne, amountOut, fee);
            } else {
                // Swap token1 partially to token0.
                zeroToOne = false;
                uint256 denominator = 1e18 - targetRatio.mulDivDown(fee, 1e6);
                amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, denominator);
            }
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V3 Pool of the Liquidity Position.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount of tokenIn that must be swapped.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced due to slippage of the swap.
     */
    function _swap(PositionState memory position, bool zeroToOne, uint256 amountIn)
        internal
        returns (bool isPoolUnbalanced_)
    {
        // Don't do swaps with zero amount.
        if (amountIn == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Do the swap.
        bytes memory data = abi.encode(position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, int256(amountIn), sqrtPriceLimitX96, data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountIn of tokenIn is swapped).
        isPoolUnbalanced_ = (amountIn > (zeroToOne ? uint256(deltaAmount0) : uint256(deltaAmount1)));
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
     * @param lowerTick The lower tick of the newly minted position.
     * @param upperTick The upper tick of the newly minted position.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id, int24 lowerTick, int24 upperTick, address initiator)
        public
        view
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        int24 currentLowerTick;
        int24 currentUpperTick;
        (,, position.token0, position.token1, position.fee, currentLowerTick, currentUpperTick, position.liquidity,,,,)
        = UniswapV3Logic.POSITION_MANAGER.positions(id);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (uint256 usdPriceToken0, uint256 usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Get data of the Liquidity Pool.
        position.pool = UniswapV3Logic._computePoolAddress(position.token0, position.token1, position.fee);
        int24 currentTick;
        (position.sqrtPriceX96, currentTick,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Store the new ticks for the rebalance
        // TODO: validate approach below for lower and upper tick
        if (lowerTick == 0 && upperTick == 0) {
            int24 tickSpacing = IUniswapV3Pool(position.pool).tickSpacing();
            int24 halfRangeTicks = ((currentUpperTick - currentLowerTick) / tickSpacing) / 2;
            halfRangeTicks *= tickSpacing;
            position.newUpperTick = currentTick + halfRangeTicks;
            position.newLowerTick = currentTick - halfRangeTicks;
        } else {
            position.newUpperTick = upperTick;
            position.newLowerTick = lowerTick;
        }

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        uint256 lowerBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        uint256 upperBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
        uint256 minSqrtRatio = TickMath.MIN_SQRT_RATIO;
        uint256 maxSqrtRatio = TickMath.MAX_SQRT_RATIO;
        position.lowerBoundSqrtPriceX96 =
            lowerBoundSqrtPriceX96 <= minSqrtRatio ? minSqrtRatio + 1 : lowerBoundSqrtPriceX96;
        position.upperBoundSqrtPriceX96 =
            upperBoundSqrtPriceX96 >= maxSqrtRatio ? maxSqrtRatio - 1 : upperBoundSqrtPriceX96;
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
