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
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint96 } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IPermit2 } from "../../lib/accounts-v2/src/interfaces/IPermit2.sol";
import { IRegistry } from "./interfaces/IRegistry.sol";
import { IUniswapV3Factory } from "./interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { SafeCastLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeCastLib.sol";
import { TickMath } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @title AutoCompounder UniswapV3
 * @author Pragma Labs
 * @notice The AutoCompounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the compounding functionality for the Account.
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

    // The contract address of the Arcadia Factory.
    IFactory internal constant FACTORY = IFactory(0xDa14Fdd72345c4d2511357214c5B89A919768e59);
    // The Uniswap V3 NonfungiblePositionManager contract.
    INonfungiblePositionManager public constant NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
    // The contract address of the Arcadia Registry.
    IRegistry internal constant REGISTRY = IRegistry(0xd0690557600eb8Be8391D1d97346e2aab5300d5f);
    // The Uniswap V3 Factory contract.
    address internal constant UNI_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // Max upper deviation in sqrtPriceX96 (reflecting the upper limit for the actual price increase)
    uint256 public immutable MAX_UPPER_SQRT_PRICE_DEVIATION;
    // Max lower deviation in sqrtPriceX96 (reflecting the lower limit for the actual price increase)
    uint256 public immutable MAX_LOWER_SQRT_PRICE_DEVIATION;
    // Basis Points (one basis point is equivalent to 0.01%)
    uint256 internal constant BIPS = 10_000;
    // Tolerance in BIPS for max price deviation and slippage
    int24 public immutable TOLERANCE;
    // Minimum fees value in USD to trigger the compounding of a position, with 18 decimals.
    uint256 public immutable MIN_USD_FEES_VALUE;
    // The fee paid on accumulated fees to the initiator, in BIPS
    uint256 public immutable INITIATOR_FEE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Storage variable for the Account to compound fees for.
    address internal account;

    // A struct with the state of a specific position.
    struct PositionState {
        address token0;
        address token1;
        uint24 fee;
        address pool;
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;
        uint160 sqrtPriceX96;
        uint256 usdPriceToken0;
        uint256 usdPriceToken1;
    }

    // A struct with variables to track the fee balances.
    struct Fees {
        uint256 amount0;
        uint256 amount1;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error CallerIsNotPool();
    error FeeValueBelowTreshold();
    error MaxToleranceExceeded();
    error MaxInitiatorFeeExceeded();
    error NotAnAccount();
    error OnlyAccount();
    error PriceToleranceExceeded();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param tolerance The max deviation of the internal pool price of assets compared to external price of assets (relative price), in BIPS.
     * @param minFeeValueInUsd The minimum USD value of the fees accumulated by a position in order to trigger the compounding. USD value with 18 decimals.
     * @param initiatorFee The fee paid to the initiator for compounding the fees, as a percentage of the accumulated fees in BIPS.
     * @dev The tolerance will be converted to an upper and lower max sqrtPrice deviation, using the square root of basis + tolerance value. As the relationship between
     * sqrtPriceX96 and actual price is quadratic, amplifying changes in the latter when the former alters slightly.
     */
    constructor(int24 tolerance, uint256 minFeeValueInUsd, uint256 initiatorFee) {
        // Tolerance should never be higher than 50%
        if (tolerance > 5000) revert MaxToleranceExceeded();
        // Initiator fee should never be higher than 20%
        if (initiatorFee > 2000) revert MaxInitiatorFeeExceeded();

        TOLERANCE = tolerance;
        MIN_USD_FEES_VALUE = minFeeValueInUsd;
        INITIATOR_FEE = initiatorFee;

        // sqrtPrice to price has a quadratic relationship thus we need to take the square root of max percentage price deviation.
        MAX_UPPER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((BIPS + uint24(tolerance)) * BIPS);
        MAX_LOWER_SQRT_PRICE_DEVIATION = FixedPointMathLib.sqrt((BIPS - uint24(tolerance)) * BIPS);
    }

    /* ///////////////////////////////////////////////////////////////
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice This function will compound the fees earned by a position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param assetId The position id to compound the fees for.
     */
    function compoundFeesForAccount(address account_, uint256 assetId) external {
        if (!FACTORY.isAccount(account_)) revert NotAnAccount();
        // Cache Account in storage, used to validate caller for executeAction()
        if (account != address(0)) revert Reentered();
        account = account_;

        address[] memory assets_ = new address[](1);
        assets_[0] = address(NONFUNGIBLE_POSITION_MANAGER);
        uint256[] memory assetIds_ = new uint256[](1);
        assetIds_[0] = assetId;
        uint256[] memory assetAmounts_ = new uint256[](1);
        assetAmounts_[0] = 1;
        uint256[] memory assetTypes_ = new uint256[](1);
        assetTypes_[0] = 2;

        ActionData memory assetData =
            ActionData({ assets: assets_, assetIds: assetIds_, assetAmounts: assetAmounts_, assetTypes: assetTypes_ });

        // Empty data needed to encode in actionData
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        bytes memory compounderData = abi.encode(assetData, msg.sender);
        bytes memory actionData = abi.encode(assetData, transferFromOwner, permit, signature, compounderData);

        // Trigger flashAction with actionTarget as this contract
        // Callback to executeAction() will be triggered.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called in the Arcadia Account.
     * @param actionData A bytes object containing one actionData struct and the address of the initiator.
     * @dev This function will trigger the following actions :
     * - Verify that the pool's current price remains within the defined tolerance range of external price.
     * - Collects the fees earned by the position.
     * - Calculates the current ratio at which fees should be deposited in position, swaps one token to another if needed.
     * - Increases the liquidity of the current position with those fees.
     * - Transfers dust amounts to the initiator.
     */
    function executeAction(bytes calldata actionData) external override returns (ActionData memory depositData) {
        // Position transferred from Account
        // Caller should be the Account provided as input in compoundFeesForAccount()
        if (msg.sender != account) revert OnlyAccount();

        // Decode bytes data
        address initiator;
        (depositData, initiator) = abi.decode(actionData, (ActionData, address));

        uint256 assetId = depositData.assetIds[0];
        PositionState memory position = _getPositionState(assetId);

        // Check that current tick of pool is not manipulated.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        _assertBalancedPool(position);

        // Collect fees
        Fees memory fees;
        {
            CollectParams memory collectParams = CollectParams({
                tokenId: assetId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
            (fees.amount0, fees.amount1) = NONFUNGIBLE_POSITION_MANAGER.collect(collectParams);
        }

        // Remove initiator reward from fees, these will be send to the initiator.
        fees.amount0 -= fees.amount0.mulDivDown(INITIATOR_FEE, BIPS);
        fees.amount1 -= fees.amount1.mulDivDown(INITIATOR_FEE, BIPS);

        // Rebalance fee amounts to match ratios of pool tick relative to ticks of the position.
        fees = _rebalanceFees(position, fees);

        // Increase liquidity in pool
        ERC20(position.token0).approve(address(NONFUNGIBLE_POSITION_MANAGER), fees.amount0);
        ERC20(position.token1).approve(address(NONFUNGIBLE_POSITION_MANAGER), fees.amount1);
        IncreaseLiquidityParams memory increaseLiquidityParams = IncreaseLiquidityParams({
            tokenId: assetId,
            amount0Desired: fees.amount0,
            amount1Desired: fees.amount1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        INonfungiblePositionManager(address(NONFUNGIBLE_POSITION_MANAGER)).increaseLiquidity(increaseLiquidityParams);

        // Dust amounts + rewards are transfered to the initiator
        ERC20(position.token0).safeTransfer(initiator, ERC20(position.token0).balanceOf(address(this)));
        ERC20(position.token1).safeTransfer(initiator, ERC20(position.token1).balanceOf(address(this)));

        // Position is deposited back to the Account
        NONFUNGIBLE_POSITION_MANAGER.approve(msg.sender, assetId);
    }

    // TODO: natspec
    function _getPositionState(uint256 assetId) internal view returns (PositionState memory position) {
        (,, position.token0, position.token1, position.fee, position.tickLower, position.tickUpper,,,,,) =
            NONFUNGIBLE_POSITION_MANAGER.positions(assetId);

        // TODO: hardcode UNI_V3_FACTORY address on Base
        position.pool =
            PoolAddress.computeAddress(address(UNI_V3_FACTORY), position.token0, position.token1, position.fee);
        (position.sqrtPriceX96, position.currentTick,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Get current prices for 1e18 amount of assets
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
    }

    /**
     * @notice Calculates the current ratio at which fees should be deposited in the position, swaps one token to another if needed.
     * @param position A struct with variables to track for a specified position.
     * @param fees A struct containing the accumulated fees of the position.
     * @return fees_ TODO
     */
    function _rebalanceFees(PositionState memory position, Fees memory fees) internal returns (Fees memory) {
        // Check value of totalFees in USD
        uint256 valueFee0 = position.usdPriceToken0.mulDivDown(fees.amount0, 1e18);
        uint256 valueFee1 = position.usdPriceToken1.mulDivDown(fees.amount1, 1e18);
        uint256 valueFeeTotal = valueFee0 + valueFee1;

        // Check that the total value of the fees in USD exceeds the threshold to initiate a rebalance.
        if (valueFeeTotal < MIN_USD_FEES_VALUE) revert FeeValueBelowTreshold();

        if (position.currentTick >= position.tickUpper) {
            // Position is fully in token 1
            // Swap full amount of token0 to token1
            fees = _swap(position, fees, true, int256(fees.amount0));
        } else if (position.currentTick <= position.tickLower) {
            // Position is fully in token 0
            // Swap full amount of token1 to token0
            fees = _swap(position, fees, false, int256(fees.amount1));
        } else {
            // Get ratio of current tick for range
            uint256 ticksInRange = uint256(int256(-position.tickLower + position.tickUpper));
            uint256 ticksFromCurrentToUpperTick = uint256(int256(-position.currentTick + position.tickUpper));

            // Get ratio of token0/token1 based on tick ratio
            // Ticks in range can't be zero (upper bound should be strictly higher than lower bound for a position)
            uint256 token0Ratio = (ticksFromCurrentToUpperTick << 24) / ticksInRange;
            uint256 targetToken0Value = (token0Ratio * (valueFee0 + valueFee1)) >> 24;

            if (targetToken0Value < valueFee0) {
                // sell token0 to token1
                uint256 amount0ToSwap = (valueFee0 - targetToken0Value).mulDivDown(fees.amount0, valueFee0);
                fees = _swap(position, fees, true, int256(amount0ToSwap));
            } else {
                // sell token1 for token0
                uint256 token1Ratio = type(uint24).max - token0Ratio;
                uint256 targetToken1Value = (token1Ratio * (valueFee0 + valueFee1)) >> 24;
                uint256 amount1ToSwap = (valueFee1 - targetToken1Value).mulDivDown(fees.amount1, valueFee1);
                fees = _swap(position, fees, false, int256(amount1ToSwap));
            }
        }

        return fees;
    }

    /* ///////////////////////////////////////////////////////////////
                             UNISWAP V3 SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // msg.sender passes data object -> untrusted!
        (address token0, address token1, uint24 fee) = abi.decode(data, (address, address, uint24));
        address pool = PoolAddress.computeAddress(UNI_V3_FACTORY, token0, token1, fee);
        if (pool != msg.sender) revert CallerIsNotPool();

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice Internal function to swap one asset for another.
     *  // TODO : natspec
     */
    function _swap(PositionState memory position, Fees memory fees, bool zeroToOne, int256 amountIn)
        internal
        returns (Fees memory)
    {
        uint256 sqrtPriceLimitX96_ = zeroToOne
            ? uint256(position.sqrtPriceX96).mulDivDown(MAX_LOWER_SQRT_PRICE_DEVIATION, BIPS)
            : uint256(position.sqrtPriceX96).mulDivDown(MAX_UPPER_SQRT_PRICE_DEVIATION, BIPS);

        bytes memory data = abi.encode(position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, amountIn, uint160(sqrtPriceLimitX96_), data);

        if ((zeroToOne && deltaAmount0 < amountIn) || (!zeroToOne && deltaAmount1 < amountIn)) {
            revert MaxToleranceExceeded();
        }

        if (zeroToOne) {
            fees.amount0 -= uint256(deltaAmount0);
            fees.amount1 += uint256(-deltaAmount1);
        } else {
            fees.amount0 += uint256(-deltaAmount0);
            fees.amount1 -= uint256(deltaAmount1);
        }

        return fees;
    }

    /* ///////////////////////////////////////////////////////////////
                     POOL PRICING TOLERANCE LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Internal function to ensure the pool's current price remains within the specified tolerance range of the external price.
     */
    // TODO : natspec
    function _assertBalancedPool(PositionState memory position) internal view {
        // Calculates current tick of the pool based on external prices
        int256 trustedTick = _getTrustedTick(position.usdPriceToken0, position.usdPriceToken1);

        // Cache tolerance.
        int24 tolerance = TOLERANCE;
        if (position.currentTick < trustedTick - tolerance || position.currentTick > trustedTick + tolerance) {
            revert PriceToleranceExceeded();
        }
    }

    /**
     * @notice Calculates the trusted tick based on external prices of both tokens.
     * @param priceToken0 The price of 1e18 tokens of token0 in USD, with 18 decimals precision.
     * @param priceToken1 The price of 1e18 tokens of token1 in USD, with 18 decimals precision.
     * @return trustedTick The trusted tick.
     * @dev The price in Uniswap V3 is defined as:
     * price = amountToken1/amountToken0.
     * The usdPriceToken is defined as: usdPriceToken = amountUsd/amountToken.
     * => amountToken = amountUsd/usdPriceToken.
     * Hence we can derive the Uniswap V3 price as:
     * price = (amountUsd/usdPriceToken1)/(amountUsd/usdPriceToken0) = usdPriceToken0/usdPriceToken1.
     */
    function _getTrustedTick(uint256 priceToken0, uint256 priceToken1) internal pure returns (int256 trustedTick) {
        if (priceToken1 == 0) return int256(uint256(TickMath.MAX_SQRT_RATIO));

        // Both priceTokens have 18 decimals precision and result of division should have 28 decimals precision.
        // -> multiply by 1e28
        // priceXd28 will overflow if priceToken0 is greater than 1.158e+49.
        // For WBTC (which only has 8 decimals) this would require a bitcoin price greater than 115 792 089 237 316 198 989 824 USD/BTC.
        uint256 priceXd28 = priceToken0.mulDivDown(1e28, priceToken1);
        // Square root of a number with 28 decimals precision has 14 decimals precision.
        uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);

        // Change sqrtPrice from a decimal fixed point number with 14 digits to a binary fixed point number with 96 digits.
        // Unsafe cast: Cast will only overflow when priceToken0/priceToken1 >= 2^128.
        uint256 sqrtPriceX96 = uint160((sqrtPriceXd14 << FixedPoint96.RESOLUTION) / 1e14);

        // Calculate trusted tick from sqrtPrice.
        trustedTick = TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX96));
    }

    /* ///////////////////////////////////////////////////////////////
                      ERC721 HANDLER FUNCTION
    /////////////////////////////////////////////////////////////// */

    /* 
    @notice Returns the onERC721Received selector.
    @dev Needed to receive ERC721 tokens.
    */
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
