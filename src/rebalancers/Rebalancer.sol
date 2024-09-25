/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { BurnLogic } from "./libraries/BurnLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FeeLogic } from "./libraries/FeeLogic.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IPool } from "./interfaces/IPool.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { MintLogic } from "./libraries/MintLogic.sol";
import { PricingLogic } from "./libraries/PricingLogic.sol";
import { RebalanceLogic } from "./libraries/RebalanceLogic.sol";
import { SafeApprove } from "./libraries/SafeApprove.sol";
import { SlipstreamLogic } from "./libraries/SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./libraries/StakedSlipstreamLogic.sol";
import { SwapLogic } from "./libraries/SwapLogic.sol";
import { SwapMath } from "./libraries/SwapMath.sol";
import { SqrtPriceMath } from "./libraries/uniswap-v3/SqrtPriceMath.sol";
import { TickMath } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";

/**
 * @title Permissioned rebalancer for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Rebalancer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Uniswap V3 Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setInitiatorForAccount() that will be permisionned to rebalance
 * all UniswapV3 Liquidity Positions held in that Account.
 * @dev The contract prevents frontrunning/sandwiching by comparing the actual pool price with a pool price calculated from trusted
 * price feeds (oracles). The tolerance in terms of price deviation is specific to the initiator but limited by a global MAX_TOLERANCE.
 * Some oracles can however deviate from the actual price by a few percent points, this could potentially open attack vectors by manipulating
 * pools and sandwiching the swap and/or increase liquidity. This asset manager should not be used for Arcadia Account that have/will have
 * Uniswap V3 Liquidity Positions where one of the underlying assets is priced with such low precision oracles.
 */
contract Rebalancer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // The maximum deviation of the actual pool price, in % with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
    // It is defined as the quotient between the minimal amount of liquidity that must be added,
    // and the amount of liquidity that would be added if the swap was executed through the pool without slippage.
    // MAX_SLIPPAGE_RATIO = minLiquidity / liquidityWithoutSlippage
    uint256 public immutable MAX_SLIPPAGE_RATIO;

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
        address tokenR;
        uint24 fee;
        int24 tickSpacing;
        int24 tickUpper;
        int24 tickLower;
        uint128 liquidity;
        uint160 sqrtRatioLower;
        uint160 sqrtRatioUpper;
        uint256 sqrtPriceX96;
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
    }

    // A struct used to store information for each specific initiator
    struct InitiatorInfo {
        uint88 upperSqrtPriceDeviation;
        uint88 lowerSqrtPriceDeviation;
        uint64 fee;
        bool initialized;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error DecreaseFeeOnly();
    error DecreaseToleranceOnly();
    error InitiatorNotValid();
    error InsufficientLiquidity();
    error MaxInitiatorFee();
    error MaxTolerance();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyPool();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Rebalance(address indexed account, address indexed positionManager, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum fee an initiator can set, with 6 decimals precision.
     * The fee is calculated on the swap amount needed to rebalance.
     */
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio) {
        MAX_TOLERANCE = maxTolerance;
        MAX_INITIATOR_FEE = maxInitiatorFee;
        MAX_SLIPPAGE_RATIO = maxSlippageRatio;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Rebalances a UniswapV3 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position to rebalance.
     * @param tickLower The new lower tick to rebalance to.
     * @param tickUpper The new upper tick to rebalance to.
     * @dev When tickLower and tickUpper are equal, ticks will be updated with same tick-spacing as current position
     * and with a balanced, 50/50 ratio around current tick.
     * @dev ToDo: should we validate the positionManager?
     */
    function rebalancePosition(
        address account_,
        address positionManager,
        uint256 id,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (ownerToAccountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InitiatorNotValid();
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData =
            ArcadiaLogic._encodeAction(positionManager, id, msg.sender, tickLower, tickUpper, swapData);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit Rebalance(account_, positionManager, id);
    }

    event Log(uint256 liquidity, uint256 minLiquidity);

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param rebalanceData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata rebalanceData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in rebalancePosition().
        if (msg.sender != account) revert OnlyAccount();

        // Decode rebalanceData.
        uint256 id;
        address positionManager;
        address initiator;
        bytes memory swapData;
        PositionState memory position;
        {
            ActionData memory assetData;
            int24 tickLower;
            int24 tickUpper;
            (assetData, initiator, tickLower, tickUpper, swapData) =
                abi.decode(rebalanceData, (ActionData, address, int24, int24, bytes));
            positionManager = assetData.assets[0];
            id = assetData.assetIds[0];

            // Fetch and cache all position related data.
            position = getPositionState(positionManager, id, tickLower, tickUpper, initiator);
        }

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Remove liquidity of the position and claim outstanding fees.
        (uint256 balance0, uint256 balance1, uint256 reward) = BurnLogic._burn(positionManager, id, position);

        // Get the rebalance parameters.
        // These are calculated based on a hypothetical swap through the pool, without slippage.
        (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut) =
        RebalanceLogic.getRebalanceParams(
            MAX_SLIPPAGE_RATIO,
            position.fee,
            initiatorInfo[initiator].fee,
            position.sqrtPriceX96,
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            balance0,
            balance1
        );

        // Do the actual swap to rebalance the position.
        // This can be done either directly through the pool, or via a router with custom swap data.
        // For swaps directly through the pool, if slippage is bigger than calculated, the transaction will not immediately revert,
        // but excess slippage will be subtracted from the initiatorFee.
        // For swaps via the router, tokenOut should be the limiting factor for increasing liquidity.
        // Leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
        // and the initiator fee will be 0 (but the transaction will not revert).
        (balance0, balance1) = SwapLogic._swap(
            positionManager, position, swapData, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
        );

        // Check that the pool is still balanced after the swap.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Mint the new liquidity position.
        // We mint with the total available balances of token0 and token1.
        uint256 newId;
        {
            uint256 liquidity;
            (newId, liquidity, balance0, balance1) = MintLogic._mint(positionManager, position, balance0, balance1);

            // Check that the actual liquidity of the position is above the minimum threshold.
            // This prevents loss of principal of the liquidity position due to slippage,
            // or malicious initiators who remove liquidity during the custom swap..
            emit Log(liquidity, minLiquidity);
            if (liquidity < minLiquidity) revert InsufficientLiquidity();
        }

        // Transfer fee to the initiator.
        (balance0, balance1) = FeeLogic._transfer(
            initiator, zeroToOne, amountInitiatorFee, position.token0, position.token1, balance0, balance1
        );

        // Approve Account to redeposit Liquidity Position and leftovers.
        {
            uint256 count = 1;
            IPositionManager(positionManager).approve(msg.sender, newId);
            if (balance0 > 0) {
                ERC20(position.token0).safeApproveWithRetry(msg.sender, balance0);
                count = 2;
            }
            if (balance1 > 0) {
                ERC20(position.token1).safeApproveWithRetry(msg.sender, balance1);
                ++count;
            }
            if (reward > 0) {
                ERC20(position.tokenR).safeApproveWithRetry(msg.sender, reward);
                ++count;
            }

            // Encode deposit data for the flash-action.
            depositData =
                ArcadiaLogic._encodeDeposit(positionManager, newId, position, count, balance0, balance1, reward);
        }

        return depositData;
    }

    /* ///////////////////////////////////////////////////////////////
                          SWAP CALLBACK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Callback after executing a swap via IPool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the pool.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the pool.
     * @param data Any data passed by this contract via the IPool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Uniswap V3 or Slipstream pool.
        (address positionManager, address token0, address token1, uint24 feeOrTickSpacing) =
            abi.decode(data, (address, address, address, uint24));
        if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
            if (UniswapV3Logic._computePoolAddress(token0, token1, feeOrTickSpacing) != msg.sender) revert OnlyPool();
        } else {
            // Logic holds for both Slipstream and staked Slipstream positions.
            if (SlipstreamLogic._computePoolAddress(token0, token1, int24(feeOrTickSpacing)) != msg.sender) {
                revert OnlyPool();
            }
        }

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    PUBLIC POSITION VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ = position.sqrtPriceX96 <= position.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 >= position.upperBoundSqrtPriceX96;
    }

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @param tickLower The lower tick of the newly minted position.
     * @param tickUpper The upper tick of the newly minted position.
     * @return position Struct with the position data.
     */
    function getPositionState(address positionManager, uint256 id, int24 tickLower, int24 tickUpper, address initiator)
        public
        view
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        (int24 tickCurrent, int24 tickRange) = positionManager == address(UniswapV3Logic.POSITION_MANAGER)
            ? UniswapV3Logic._getPositionState(position, id, tickLower == tickUpper)
            // Logic holds for both Slipstream and staked Slipstream positions.
            : SlipstreamLogic._getPositionState(position, id);

        if (positionManager == address(StakedSlipstreamLogic.POSITION_MANAGER)) {
            StakedSlipstreamLogic._getPositionState(position);
        }

        // Store the new ticks for the rebalance
        if (tickLower == tickUpper) {
            // Round current tick down to a tick that is a multiple of the tick spacing (can be initialised).
            // ToDo: handle TICK_MAX and TICK_MIN
            tickCurrent = tickCurrent / position.tickSpacing * position.tickSpacing;
            (position.tickLower, position.tickUpper) = tickRange > position.tickSpacing
                ? (tickCurrent - tickRange / 2, tickCurrent + tickRange / 2)
                : (tickCurrent, tickCurrent + tickRange);
        } else {
            (position.tickLower, position.tickUpper) = (tickLower, tickUpper);
        }

        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.tickUpper);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (uint256 usdPriceToken0, uint256 usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        uint256 lowerBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        uint256 upperBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
        position.lowerBoundSqrtPriceX96 =
            lowerBoundSqrtPriceX96 <= TickMath.MIN_SQRT_RATIO ? TickMath.MIN_SQRT_RATIO + 1 : lowerBoundSqrtPriceX96;
        position.upperBoundSqrtPriceX96 =
            upperBoundSqrtPriceX96 >= TickMath.MAX_SQRT_RATIO ? TickMath.MAX_SQRT_RATIO - 1 : upperBoundSqrtPriceX96;
    }

    /* ///////////////////////////////////////////////////////////////
                        INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */
    /**
     * @notice Sets an initiator for an Account. An initiator will be permissioned to rebalance any UniswapV3
     * Liquidity Position held in the specified Arcadia Account.
     * @param initiator The address of the initiator.
     * @param account_ The address of the Arcadia Account to set an initiator for.
     */
    function setInitiatorForAccount(address initiator, address account_) external {
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        ownerToAccountToInitiator[msg.sender][account_] = initiator;
    }

    /**
     * @notice Sets the information requested for an initiator.
     * @param fee The fee paid to to the initiator, with 6 decimals precision.
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

        initiatorInfo_.fee = uint64(fee);

        // SQRT_PRICE_DEVIATION is the square root of maximum/minimum price deviation.
        // Sqrt halves the number of decimals.
        uint88 upperSqrtPriceDeviation = uint88(FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));
        if (initiatorInfo_.initialized == true && upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation) {
            revert DecreaseToleranceOnly();
        }

        initiatorInfo_.lowerSqrtPriceDeviation = uint88(FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18));
        initiatorInfo_.upperSqrtPriceDeviation = upperSqrtPriceDeviation;

        // Set initiator as initialized if it wasn't already.
        if (initiatorInfo_.initialized == false) initiatorInfo_.initialized = true;

        initiatorInfo[msg.sender] = initiatorInfo_;
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
