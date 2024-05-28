/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { AssetValueAndRiskFactors } from "../../lib/accounts-v2/src/libraries/AssetValuationLib.sol";
import {
    CollectParams,
    IncreaseLiquidityParams,
    INonfungiblePositionManager
} from "./interfaces/INonfungiblePositionManager.sol";
import { EncodeActionData } from "./libraries/EncodeActionData.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IQuoter } from "./interfaces/IQuoter.sol";
import { IRegistry } from "./interfaces/IRegistry.sol";
import { IUniswapV3Factory } from "./interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";

/**
 * @title AutoCompounder UniswapV3
 * @author Pragma Labs
 * @notice The AutoCompounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the compounding functionality for an Uniswap V3 Liquidity Position in the Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 */
contract AutoCompounder is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum share of the fees paid to the initiator as reward, with 18 decimals precision.
    uint256 internal constant MAX_INITIATOR_SHARE = 0.5 * 1e18; // 5%
    // The maximum tolerance, with 18 decimals precision.
    uint256 internal constant MAX_TOLERANCE = 0.5 * 1e18; // 5%
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

    // The contract address of the Arcadia Factory.
    IFactory internal constant FACTORY = IFactory(0xDa14Fdd72345c4d2511357214c5B89A919768e59);
    // The Uniswap V3 NonfungiblePositionManager contract.
    INonfungiblePositionManager public constant NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
    // The Uniswap V3 Quoter contract.
    IQuoter internal constant QUOTER = IQuoter(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);
    // The contract address of the Arcadia Registry.
    IRegistry internal constant REGISTRY = IRegistry(0xd0690557600eb8Be8391D1d97346e2aab5300d5f);

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
        int256 tickLower;
        int256 tickUpper;
        int256 currentTick;
        uint256 sqrtPriceX96;
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

    error BelowTreshold();
    error MaxInitiatorShareExceeded();
    error MaxToleranceExceeded();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyPool();
    error Reentered();
    error UnbalancedPool();

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
     * using the square root of the basis (one with 18 decimals precision) + tolerance value (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPriceX96 for the lower and upper boundaries.
     */
    constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance) {
        // Tolerance should never be more than 5%.
        if (tolerance > MAX_TOLERANCE) revert MaxToleranceExceeded();
        // Initiator reward should never be more than 5%.
        if (initiatorShare > MAX_INITIATOR_SHARE) revert MaxInitiatorShareExceeded();

        COMPOUND_THRESHOLD = compoundThreshold;
        INITIATOR_SHARE = initiatorShare;

        // sqrtPrice to price has a quadratic relationship, thus we need to take the square root of max percentage price deviation.
        LOWER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        UPPER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
    }

    /* ///////////////////////////////////////////////////////////////
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice This function will compound the fees earned by a position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the UniswapV3 Liquidity Position to compound the fees for.
     */
    function compoundFees(address account_, uint256 id) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (!FACTORY.isAccount(account_)) revert NotAnAccount();
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = EncodeActionData._encode(msg.sender, address(NONFUNGIBLE_POSITION_MANAGER), id);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param compoundData A bytes object containing one assetData struct and the address of the initiator.
     * @return assetData A struct with the asset data of the Liquidity Position.
     * @dev This function will trigger the following actions :
     * - Verify that the pool's current price is initially within the defined tolerance range of external price.
     * - Collects the fees earned by the position.
     * - Verify that the fee value is bigger than the threshold required to trigger a compoundFees.
     * - Rebalance the fee amounts so that the maximum amount of liquidity can be added, swaps one token to another if needed.
     * - Verify that the pool's price is still within the defined tolerance range of external price after the swap.
     * - Increases the liquidity of the current position with those fees.
     * - Transfers a reward + dust amounts to the initiator.
     */
    function executeAction(bytes calldata compoundData) external override returns (ActionData memory assetData) {
        // Position transferred from Account
        // Caller should be the Account provided as input in compoundFees()
        if (msg.sender != account) revert OnlyAccount();

        // Decode compoundData
        address initiator;
        (assetData, initiator) = abi.decode(compoundData, (ActionData, address));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        PositionState memory position = _getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (_isUnBalanced(position)) revert UnbalancedPool();

        // Collect fees.
        Fees memory fees;
        CollectParams memory collectParams = CollectParams({
            tokenId: id,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (fees.amount0, fees.amount1) = NONFUNGIBLE_POSITION_MANAGER.collect(collectParams);

        // Subtract initiator reward from fees, these will be send to the initiator.
        fees.amount0 -= fees.amount0.mulDivDown(INITIATOR_SHARE, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(INITIATOR_SHARE, 1e18);

        // Total value of the fees that will be compounded must be greater than the threshold.
        uint256 valueFee0 = position.usdPriceToken0.mulDivDown(fees.amount0, 1e18);
        uint256 valueFee1 = position.usdPriceToken1.mulDivDown(fees.amount1, 1e18);
        uint256 totalValueFees = valueFee0 + valueFee1;
        if (totalValueFees < COMPOUND_THRESHOLD) revert BelowTreshold();

        // Rebalance the fee amounts so that the maximum amount of liquidity can be added.
        (bool zeroToOne, uint256 amountIn) = _getSwapParameters(position, fees, valueFee1, totalValueFees);
        bool isUnBalanced;
        (isUnBalanced, fees) = _swap(position, fees, zeroToOne, int256(amountIn));

        // Check that the Pool is still balanced after the swap.
        // Slippage would result in leftover fees after increasing liquidity.
        // These leftovers would go to the initiator instead to the position owner.
        if (isUnBalanced) revert UnbalancedPool();

        // Increase liquidity of the position.
        ERC20(position.token0).approve(address(NONFUNGIBLE_POSITION_MANAGER), fees.amount0);
        ERC20(position.token1).approve(address(NONFUNGIBLE_POSITION_MANAGER), fees.amount1);
        IncreaseLiquidityParams memory increaseLiquidityParams = IncreaseLiquidityParams({
            tokenId: id,
            amount0Desired: fees.amount0,
            amount1Desired: fees.amount1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        INonfungiblePositionManager(address(NONFUNGIBLE_POSITION_MANAGER)).increaseLiquidity(increaseLiquidityParams);

        // Initiator rewards and leftover assets after swap() and increaseLiquidity() are transferred to the initiator.
        ERC20(position.token0).safeTransfer(initiator, ERC20(position.token0).balanceOf(address(this)));
        ERC20(position.token1).safeTransfer(initiator, ERC20(position.token1).balanceOf(address(this)));

        // Approve Account to deposited Liquidity Position back into the Account
        NONFUNGIBLE_POSITION_MANAGER.approve(msg.sender, id);
    }

    /* ///////////////////////////////////////////////////////////////
                        POSITION STATE LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from third part contracts.
     * @param id The id of the Liquidity Position.
     * @return position Struct with the position data.
     */
    function _getPositionState(uint256 id) internal view returns (PositionState memory position) {
        (,, position.token0, position.token1, position.fee, position.tickLower, position.tickUpper,,,,,) =
            NONFUNGIBLE_POSITION_MANAGER.positions(id);

        // Get current USD prices for 1e18 gwei of assets.
        address[] memory assets = new address[](2);
        assets[0] = position.token0;
        assets[1] = position.token1;
        uint256[] memory assetAmounts = new uint256[](2);
        assetAmounts[0] = 1e18;
        assetAmounts[1] = 1e18;

        AssetValueAndRiskFactors[] memory valuesAndRiskFactors =
            REGISTRY.getValuesInUsd(address(0), assets, new uint256[](2), assetAmounts);
        position.usdPriceToken0 = valuesAndRiskFactors[0].assetValue;
        position.usdPriceToken1 = valuesAndRiskFactors[1].assetValue;

        position.pool = PoolAddress.computeAddress(
            UniswapV3Logic.UNISWAP_V3_FACTORY, position.token0, position.token1, position.fee
        );
        (position.sqrtPriceX96, position.currentTick,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(position.usdPriceToken0, position.usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        position.lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(LOWER_SQRT_PRICE_DEVIATION, 1e18);
        position.upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(UPPER_SQRT_PRICE_DEVIATION, 1e18);
    }

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isUnBalanced Bool indicating if the pool is unbalanced.
     */
    function _isUnBalanced(PositionState memory position) internal pure returns (bool isUnBalanced) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isUnBalanced = position.sqrtPriceX96 < position.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 > position.upperBoundSqrtPriceX96;
    }

    /* ///////////////////////////////////////////////////////////////
                        SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice returns the swap parameters to optimize the total value of fees that can be added as liquidity.
     * @param position Struct with the position data.
     * @param fees Struct with the fee balances.
     * @param valueFee1 The USD value of the amount of fees of token1, with 18 decimals precision.
     * @param totalValueFees The USD value of the total amount fees, with 18 decimals precision.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountIn The amount that of tokenIn that must be swapped to tokenOut.
     * @dev We assume the fees amount are small compared to the liquidity of the pool,
     * hence we neglect slippage when optimizing the swap amounts (this is enforced after the swap).
     */
    function _getSwapParameters(
        PositionState memory position,
        Fees memory fees,
        uint256 valueFee1,
        uint256 totalValueFees
    ) internal pure returns (bool zeroToOne, uint256 amountIn) {
        if (position.currentTick >= position.tickUpper) {
            // Position is fully in token 1
            // Swap full amount of token0 to token1
            return (true, fees.amount0);
        } else if (position.currentTick <= position.tickLower) {
            // Position is fully in token 0
            // Swap full amount of token1 to token0
            return (false, fees.amount1);
        } else {
            // Position is in range.
            // Rebalance fees so that the ratio of the fee values matches with ratio of the ticks.
            uint256 ticksLowerToUpper = uint256(position.tickUpper - position.tickLower);
            uint256 ticksCurrentToUpper = uint256(position.tickUpper - position.currentTick);
            uint256 targetRatio = ticksCurrentToUpper.mulDivDown(1e18, ticksLowerToUpper);

            uint256 currentRatio = valueFee1.mulDivDown(1e18, totalValueFees);

            if (currentRatio < targetRatio) {
                // Swap token0 partially to token1.
                amountIn = (targetRatio - currentRatio).mulDivDown(totalValueFees, position.usdPriceToken0);
                zeroToOne = true;
            } else {
                // Swap token1 partially to token0.
                amountIn = (currentRatio - targetRatio).mulDivDown(totalValueFees, position.usdPriceToken1);
                zeroToOne = false;
            }
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V3 Pool of the Liquidity Position.
     * @param position Struct with the position data.
     * @param fees Struct with the fee balances.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount that of tokenIn that must be swapped to tokenOut.
     * @return isUnBalanced Bool indicating if the pool is unbalanced due to slippage after the swap.
     * @return fees Struct with the updated fee balances.
     */
    function _swap(PositionState memory position, Fees memory fees, bool zeroToOne, int256 amountIn)
        internal
        returns (bool, Fees memory)
    {
        // Max slippage: Pool should still be balanced after the swap.
        uint256 sqrtPriceLimitX96 = zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96;

        // Do the swap.
        bytes memory data = abi.encode(position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, amountIn, uint160(sqrtPriceLimitX96), data);

        // Check if max slippage was not exceeded (not all amountIn is swapped before sqrtPriceLimitX96 is reached).
        bool isUnBalanced = (amountIn < (zeroToOne ? deltaAmount0 : deltaAmount1));

        // Update the fee balances.
        fees.amount0 = zeroToOne ? fees.amount0 - uint256(deltaAmount0) : fees.amount0 + uint256(-deltaAmount0);
        fees.amount1 = zeroToOne ? fees.amount1 + uint256(-deltaAmount1) : fees.amount1 - uint256(deltaAmount1);

        return (isUnBalanced, fees);
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
        address pool = PoolAddress.computeAddress(UniswapV3Logic.UNISWAP_V3_FACTORY, token0, token1, fee);
        if (pool != msg.sender) revert OnlyPool();

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                      OFFCHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @return fees Struct with the final fee balances.
     * @dev While this function does not persist state changes, it cannot be declared as view function,
     * since quoteExactInputSingle() of Uniswaps Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id) external returns (bool isCompoundable_, Fees memory fees) {
        // Fetch and cache all position related data.
        PositionState memory position = _getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (_isUnBalanced(position)) return (false, fees);

        // Get fee amounts
        (fees.amount0, fees.amount1) = UniswapV3Logic._getFeeAmounts(NONFUNGIBLE_POSITION_MANAGER, id);

        // Remove initiator reward from fees, these will be send to the initiator.
        fees.amount0 -= fees.amount0.mulDivDown(INITIATOR_SHARE, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(INITIATOR_SHARE, 1e18);

        // Total value of the compounded fees should be greater than the threshold
        uint256 valueFee0 = position.usdPriceToken0.mulDivDown(fees.amount0, 1e18);
        uint256 valueFee1 = position.usdPriceToken1.mulDivDown(fees.amount1, 1e18);
        uint256 totalValueFees = valueFee0 + valueFee1;
        if (totalValueFees < COMPOUND_THRESHOLD) return (false, fees);

        // Calculate fee amounts to match ratios of current pool tick relative to ticks of the position.
        // Pool should still be balanced after the swap.
        (bool zeroToOne, uint256 amountIn) = _getSwapParameters(position, fees, valueFee1, totalValueFees);
        bool isUnBalanced;
        (isUnBalanced, fees) = _quote(position, fees, zeroToOne, amountIn);

        return (!isUnBalanced, fees);
    }

    /**
     * @notice Off-chain view function to get the quote of a swap.
     * @param position Struct with the position data.
     * @param fees Struct with the fee balances.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount that of tokenIn that must be swapped to tokenOut.
     * @return isUnBalanced Bool indicating if the pool is unbalanced due to slippage after the swap.
     * @return fees Struct with the updated fee balances.
     * @dev While this function does not persist state changes, it cannot be declared as view function,
     * since quoteExactInputSingle() of Uniswaps Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function _quote(PositionState memory position, Fees memory fees, bool zeroToOne, uint256 amountIn)
        internal
        returns (bool, Fees memory)
    {
        // Max slippage: Pool should still be balanced after the swap.
        uint256 sqrtPriceLimitX96 = zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96;

        // Quote the swap.
        (uint256 amountOut, uint160 sqrtPriceX96After,,) = QUOTER.quoteExactInputSingle(
            IQuoter.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? position.token0 : position.token1,
                tokenOut: zeroToOne ? position.token1 : position.token0,
                amountIn: amountIn,
                fee: position.fee,
                sqrtPriceLimitX96: uint160(sqrtPriceLimitX96)
            })
        );

        // Check if max slippage was exceeded (sqrtPriceLimitX96 is reached).
        bool isUnBalanced = sqrtPriceX96After == sqrtPriceLimitX96 ? true : false;

        // Update the fee balances.
        fees.amount0 = zeroToOne ? fees.amount0 - amountIn : fees.amount0 + amountOut;
        fees.amount1 = zeroToOne ? fees.amount1 + amountOut : fees.amount1 - amountIn;

        return (isUnBalanced, fees);
    }

    /* ///////////////////////////////////////////////////////////////
                      ERC721 HANDLER FUNCTION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the onERC721Received selector.
     * @dev Needed to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
