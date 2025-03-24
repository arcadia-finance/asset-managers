/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IPermit2 } from "../interfaces/IPermit2.sol";
import { IPoolManager, ModifyLiquidityParams, SwapParams } from "./interfaces/IPoolManager.sol";
import { LiquidityAmounts } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    PositionInfoLibrary,
    PositionInfo
} from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV4Logic } from "./libraries/UniswapV4Logic.sol";

/**
 * @title Permissionless and Stateless Compounder for UniswapV4 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the compounding functionality for a Uniswap V4 Liquidity Position in the Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The contract prevents frontrunning/sandwiching by comparing the actual pool price with a pool price calculated from trusted
 * price feeds (oracles).
 * Some oracles can however deviate from the actual price by a few percent points, this could potentially open attack vectors by manipulating
 * pools and sandwiching the swap and/or increase liquidity. This asset manager should not be used for Arcadia Account that have/will have
 * Uniswap V4 Liquidity Positions where one of the underlying assets is priced with such low precision oracles.
 */
contract UniswapV4Compounder is IActionBase {
    using BalanceDeltaLibrary for BalanceDelta;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The Permit2 contract.
    IPermit2 internal constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

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
    error PoolManagerOnly();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Compound(address indexed account, uint256 id);

    event LogUint(uint256);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @dev Only the UniswapV4 PoolManager can call functions with this modifier.
     */
    modifier onlyPoolManager() {
        if (msg.sender != address(UniswapV4Logic.POOL_MANAGER)) revert PoolManagerOnly();
        _;
    }

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
     * @notice Compounds the fees earned by a UniswapV4 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the Liquidity Position.
     */
    function compoundFees(address account_, uint256 id) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData =
            ArcadiaLogic._encodeActionData(msg.sender, address(UniswapV4Logic.POSITION_MANAGER), id);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

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
        (assetData, initiator) = abi.decode(compoundData, (ActionData, address));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        (PositionState memory position, PoolKey memory poolKey) = getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Collect fees.
        Fees memory fees;
        (fees.amount0, fees.amount1) = _collectFees(id, poolKey);

        // Total value of the fees must be greater than the threshold.
        if (isBelowThreshold(position, fees)) revert BelowThreshold();

        // Subtract initiator reward from fees, these will be send to the initiator.
        fees.amount0 -= fees.amount0.mulDivDown(INITIATOR_SHARE, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(INITIATOR_SHARE, 1e18);

        // Rebalance the fee amounts so that the maximum amount of liquidity can be added.
        // The Pool must still be balanced after the swap.
        (bool zeroToOne, uint256 amountOut) = getSwapParameters(position, fees);
        uint256 tokenInBeforeSwap = zeroToOne ? poolKey.currency0.balanceOfSelf() : poolKey.currency1.balanceOfSelf();
        if (_swap(poolKey, position.lowerBoundSqrtPriceX96, position.upperBoundSqrtPriceX96, zeroToOne, amountOut)) {
            revert UnbalancedPool();
        }
        uint256 tokenInAfterSwap = zeroToOne ? poolKey.currency0.balanceOfSelf() : poolKey.currency1.balanceOfSelf();

        // We increase the fee amount of tokenOut, but we do not decrease the fee amount of tokenIn.
        // This guarantees that tokenOut is the limiting factor when increasing liquidity and not tokenIn.
        // As a consequence, slippage will result in less tokenIn going to the initiator,
        // instead of more tokenOut going to the initiator.
        if (zeroToOne) {
            fees.amount1 += amountOut;
            fees.amount0 -= (tokenInBeforeSwap - tokenInAfterSwap);
        } else {
            fees.amount0 += amountOut;
            fees.amount1 -= (tokenInBeforeSwap - tokenInAfterSwap);
        }

        // Increase liquidity of the position.
        // Handle approvals based on whether tokens are ETH or ERC20.
        bool token0IsNative = Currency.unwrap(poolKey.currency0) == address(0);

        // Handle approvals for non-native tokens
        if (!token0IsNative && fees.amount0 > 0) {
            _checkAndApprovePermit2(Currency.unwrap(poolKey.currency0), fees.amount0);
        }
        if (fees.amount1 > 0) _checkAndApprovePermit2(Currency.unwrap(poolKey.currency1), fees.amount1);

        {
            // Calculate liquidity to be added based on fee amounts and updated sqrtPriceX96 after swap.
            (uint160 newSqrtPriceX96,,,) = UniswapV4Logic.STATE_VIEW.getSlot0(poolKey.toId());
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                newSqrtPriceX96,
                uint160(position.sqrtRatioLower),
                uint160(position.sqrtRatioUpper),
                fees.amount0,
                fees.amount1
            );

            uint256 ethValue = token0IsNative ? fees.amount0 : 0;

            // Generate calldata to increase liquidity.
            bytes memory actions = new bytes(2);
            actions[0] = bytes1(uint8(UniswapV4Logic.INCREASE_LIQUIDITY));
            actions[1] = bytes1(uint8(UniswapV4Logic.SETTLE_PAIR));
            bytes[] memory params = new bytes[](2);
            params[0] = abi.encode(id, liquidity, type(uint128).max, type(uint128).max, "");
            params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

            bytes memory increaseLiquidityParams = abi.encode(actions, params);
            UniswapV4Logic.POSITION_MANAGER.modifyLiquidities{ value: ethValue }(
                increaseLiquidityParams, block.timestamp
            );
        }

        // Initiator rewards are transferred to the initiator.
        uint256 balance0 = poolKey.currency0.balanceOfSelf();
        uint256 balance1 = poolKey.currency1.balanceOfSelf();

        if (balance0 > 0) poolKey.currency0.transfer(initiator, balance0);
        if (balance1 > 0) poolKey.currency1.transfer(initiator, balance1);

        // Approve Account to deposit Liquidity Position back into the Account.
        UniswapV4Logic.POSITION_MANAGER.approve(msg.sender, id);
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
            amountOut = UniswapV4Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
        } else if (position.sqrtPriceX96 <= position.sqrtRatioLower) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            zeroToOne = false;
            amountOut = UniswapV4Logic._getAmountOut(position.sqrtPriceX96, false, fees.amount1);
        } else {
            // Position is in range.
            // Rebalance fees so that the ratio of the fee values matches with ratio of the position.
            uint256 targetRatio =
                UniswapV4Logic._getTargetRatio(position.sqrtPriceX96, position.sqrtRatioLower, position.sqrtRatioUpper);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV4Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
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
                amountOut = UniswapV4Logic._getAmountOut(position.sqrtPriceX96, false, amountIn);
            }
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V4 Pool of the Liquidity Position.
     * @param poolKey The key containing pool parameters.
     * @param lowerBoundSqrtPriceX96 The minimum acceptable sqrt price after swap (used when swapping token0 for token1).
     * @param upperBoundSqrtPriceX96 The maximum acceptable sqrt price after swap (used when swapping token1 for token0).
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced due to slippage of the swap.
     */
    function _swap(
        PoolKey memory poolKey,
        uint256 lowerBoundSqrtPriceX96,
        uint256 upperBoundSqrtPriceX96,
        bool zeroToOne,
        uint256 amountOut
    ) internal returns (bool isPoolUnbalanced_) {
        // Don't do swaps with zero amount.
        if (amountOut == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 = uint160(zeroToOne ? lowerBoundSqrtPriceX96 : upperBoundSqrtPriceX96);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroToOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        bytes memory swapData = abi.encode(params, poolKey);
        // Do the swap.
        bytes memory results = UniswapV4Logic.POOL_MANAGER.unlock(swapData);
        BalanceDelta swapDelta = abi.decode(results, (BalanceDelta));

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        isPoolUnbalanced_ = (amountOut > (zeroToOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0())));
    }

    /**
     * @notice Collects fees for a specific liquidity position in a Uniswap V4 pool.
     * @param tokenId The id of the liquidity position in UniswapV4 PositionManager.
     * @param poolKey The key containing pool parameters.
     * @return feeAmount0 The amount of fees collected in terms of token0.
     * @return feeAmount1 The amount of fees collected in terms of token1.
     */
    function _collectFees(uint256 tokenId, PoolKey memory poolKey)
        internal
        returns (uint256 feeAmount0, uint256 feeAmount1)
    {
        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(UniswapV4Logic.DECREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(UniswapV4Logic.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

        // Cache init balance of token0 and token1.
        uint256 initBalanceCurrency0 = poolKey.currency0.balanceOfSelf();
        uint256 initBalanceCurrency1 = poolKey.currency1.balanceOfSelf();

        bytes memory decreaseLiquidityParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities(decreaseLiquidityParams, block.timestamp);

        feeAmount0 = poolKey.currency0.balanceOfSelf() - initBalanceCurrency0;
        feeAmount1 = poolKey.currency1.balanceOfSelf() - initBalanceCurrency1;
    }

    /**
     * @notice Callback function executed during the unlock phase of a Uniswap V4 pool operation.
     * @dev This function can only be called by the Pool Manager. It processes a swap and handles the resulting balance deltas.
     * @param data The encoded swap parameters and pool key.
     * @return results The encoded BalanceDelta result from the swap operation.
     */
    function unlockCallback(bytes calldata data) external payable onlyPoolManager returns (bytes memory results) {
        (SwapParams memory params, PoolKey memory poolKey) = abi.decode(data, (SwapParams, PoolKey));
        BalanceDelta delta = UniswapV4Logic.POOL_MANAGER.swap(poolKey, params, "");

        UniswapV4Logic._processSwapDelta(delta, poolKey.currency0, poolKey.currency1);
        results = abi.encode(delta);
    }

    /* ///////////////////////////////////////////////////////////////
                    POSITION AND POOL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id)
        public
        view
        virtual
        returns (PositionState memory position, PoolKey memory poolKey)
    {
        PositionInfo info;
        (poolKey, info) = UniswapV4Logic.POSITION_MANAGER.getPoolAndPositionInfo(id);

        // Get data of the Liquidity Position.
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(info.tickLower());
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(info.tickUpper());
        // TODO: try to access via PoolManager instead of StateView, but fails.
        (position.sqrtPriceX96,,,) = UniswapV4Logic.STATE_VIEW.getSlot0(poolKey.toId());
        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (position.usdPriceToken0, position.usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1));

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(position.usdPriceToken0, position.usdPriceToken1);

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
                        PERMIT2 APPROVALS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Ensures that the Permit2 contract has sufficient approval to spend a given token
     *         and grants unlimited approval to the PositionManager via Permit2.
     * @dev This function performs two key approval steps:
     *      1. Approves Permit2 to spend the specified token.
     *      2. Approves the PositionManager to spend the token through Permit2.
     * @dev If the token requires resetting the approval to zero before setting a new value,
     *      this function first resets the approval to `0` before setting it to `type(uint256).max`.
     * @param token The address of the ERC20 token to approve.
     * @param amount The minimum amount required to be approved.
     */
    function _checkAndApprovePermit2(address token, uint256 amount) internal {
        uint256 currentAllowance =
            PERMIT_2.allowance(address(this), token, address(UniswapV4Logic.POSITION_MANAGER)).amount;

        if (currentAllowance < amount) {
            ERC20(token).safeApprove(address(PERMIT_2), 0);
            ERC20(token).safeApprove(address(PERMIT_2), type(uint256).max);
            PERMIT_2.approve(token, address(UniswapV4Logic.POSITION_MANAGER), type(uint160).max, type(uint48).max);
        }
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

    /* ///////////////////////////////////////////////////////////////
                      NATIVE ETH FUNCTION
    /////////////////////////////////////////////////////////////// */

    // Function to receive native ETH.
    receive() external payable { }
}
