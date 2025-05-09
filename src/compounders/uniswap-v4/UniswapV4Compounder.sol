/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Actions } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/Actions.sol";
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
import { IPoolManager } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { LiquidityAmounts } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    PositionInfoLibrary,
    PositionInfo
} from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { SafeApprove } from "../../libraries/SafeApprove.sol";
import { StateLibrary } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4Logic } from "./libraries/UniswapV4Logic.sol";

/**
 * @title Compounder for UniswapV4 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the compounding functionality for a Uniswap V4 Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to compound the positions in their Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of compounding to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the compounding process,
 * ensuring that the execution remains within a controlled price range.
 */
contract UniswapV4Compounder is IActionBase {
    using BalanceDeltaLibrary for BalanceDelta;
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    using StateLibrary for IPoolManager;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum deviation of the actual pool price copared the price given by the initiator, with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The Permit2 contract.
    IPermit2 internal constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to compound the fees for, used as transient storage.
    address internal account;

    // A mapping if permit2 has been approved for a certain token.
    mapping(address token => bool approved) internal approved;

    // A mapping from initiator to a struct with initiator-specific tolerance and fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

    // A mapping that sets the approved initiator per account.
    mapping(address account => address initiator) public accountToInitiator;

    // A struct with the state of a specific position, only used in memory.
    struct PositionState {
        uint256 sqrtPrice;
        uint256 sqrtRatioLower;
        uint256 sqrtRatioUpper;
        uint256 lowerBoundSqrtPrice;
        uint256 upperBoundSqrtPrice;
    }

    // A struct with variables to track the fee balances, only used in memory.
    struct Fees {
        uint256 amount0;
        uint256 amount1;
    }

    // A struct with information for each specific initiator
    struct InitiatorInfo {
        uint64 upperSqrtPriceDeviation;
        uint64 lowerSqrtPriceDeviation;
        uint64 fee;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InitiatorNotValid();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyPool();
    error PoolManagerOnly();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Compound(address indexed account, uint256 id);
    event InitiatorSet(address indexed account, address indexed initiator);

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
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum initiator fee an initiator can set.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPrice for the lower and upper boundaries.
     */
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee) {
        MAX_INITIATOR_FEE = maxInitiatorFee;
        MAX_TOLERANCE = maxTolerance;
    }

    /* ///////////////////////////////////////////////////////////////
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Compounds the fees earned by a UniswapV4 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param id The id of the Liquidity Position.
     * @param trustedSqrtPrice The trusted sqrtPrice of the pool, provided by the initiator.
     */
    function compoundFees(address account_, uint256 id, uint256 trustedSqrtPrice) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InitiatorNotValid();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData =
            ArcadiaLogic._encodeActionData(msg.sender, address(UniswapV4Logic.POSITION_MANAGER), id, trustedSqrtPrice);

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
     * - Rebalance the fee amounts so that the maximum amount of liquidity can be added, swaps one token to another if needed.
     * - Verify that the pool's price is still within the defined tolerance price range after the swap.
     * - Increases the liquidity of the current position with those fees.
     * - Transfers an initiator fee + dust amounts to the initiator.
     */
    function executeAction(bytes calldata compoundData) external override returns (ActionData memory assetData) {
        // Caller should be the Account, provided as input in compoundFees().
        if (msg.sender != account) revert OnlyAccount();

        // Decode compoundData.
        address initiator;
        uint256 trustedSqrtPrice;
        (assetData, initiator, trustedSqrtPrice) = abi.decode(compoundData, (ActionData, address, uint256));
        uint256 id = assetData.assetIds[0];

        // Fetch and cache all position related data.
        (PositionState memory position, PoolKey memory poolKey) = getPositionState(id, trustedSqrtPrice, initiator);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Collect fees.
        Fees memory fees;
        (fees.amount0, fees.amount1) = _collectFees(id, poolKey);

        // Subtract initiator fee from collected fees, these will be send to the initiator.
        uint256 initiatorFee = uint256(initiatorInfo[initiator].fee);
        fees.amount0 -= fees.amount0.mulDivDown(initiatorFee, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(initiatorFee, 1e18);

        // Rebalance the fee amounts so that the maximum amount of liquidity can be added.
        // The Pool must still be balanced after the swap.
        (bool zeroToOne, uint256 amountOut) = getSwapParameters(position, fees);
        if (_swap(poolKey, position.lowerBoundSqrtPrice, position.upperBoundSqrtPrice, zeroToOne, amountOut)) {
            revert UnbalancedPool();
        }

        // We increase the fee amount of tokenOut, but we do not decrease the fee amount of tokenIn.
        // This guarantees that tokenOut is the limiting factor when increasing liquidity and not tokenIn.
        // As a consequence, slippage will result in less tokenIn going to the initiator,
        // instead of more tokenOut going to the initiator.
        if (zeroToOne) fees.amount1 += amountOut;
        else fees.amount0 += amountOut;

        // Increase liquidity of the position.
        _mint(poolKey, fees.amount0, fees.amount1, position.sqrtRatioLower, position.sqrtRatioUpper, id);

        // Initiator fees are transferred to the initiator.
        uint256 balance0 = poolKey.currency0.balanceOfSelf();
        uint256 balance1 = poolKey.currency1.balanceOfSelf();
        if (balance0 > 0) poolKey.currency0.transfer(initiator, balance0);
        if (balance1 > 0) poolKey.currency1.transfer(initiator, balance1);

        // Approve Account to deposit Liquidity Position back into the Account.
        UniswapV4Logic.POSITION_MANAGER.approve(msg.sender, id);
    }

    /* ///////////////////////////////////////////////////////////////
                        FEE COLLECTION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Collects fees for a specific liquidity position in a Uniswap V4 pool.
     * @param id The id of the liquidity position in UniswapV4 PositionManager.
     * @param poolKey The key containing pool parameters.
     * @return feeAmount0 The amount of fees collected in terms of token0.
     * @return feeAmount1 The amount of fees collected in terms of token1.
     */
    function _collectFees(uint256 id, PoolKey memory poolKey)
        internal
        returns (uint256 feeAmount0, uint256 feeAmount1)
    {
        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(id, 0, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

        bytes memory decreaseLiquidityParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities(decreaseLiquidityParams, block.timestamp);

        feeAmount0 = poolKey.currency0.balanceOfSelf();
        feeAmount1 = poolKey.currency1.balanceOfSelf();
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
        if (position.sqrtPrice >= position.sqrtRatioUpper) {
            // Position is out of range and fully in token 1.
            // Swap full amount of token0 to token1.
            zeroToOne = true;
            amountOut = UniswapV4Logic._getAmountOut(position.sqrtPrice, true, fees.amount0);
        } else if (position.sqrtPrice <= position.sqrtRatioLower) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            zeroToOne = false;
            amountOut = UniswapV4Logic._getAmountOut(position.sqrtPrice, false, fees.amount1);
        } else {
            // Position is in range.
            // Rebalance fees so that the ratio of the fee values matches with ratio of the position.
            uint256 targetRatio =
                UniswapV4Logic._getTargetRatio(position.sqrtPrice, position.sqrtRatioLower, position.sqrtRatioUpper);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV4Logic._getAmountOut(position.sqrtPrice, true, fees.amount0);
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
                amountOut = UniswapV4Logic._getAmountOut(position.sqrtPrice, false, amountIn);
            }
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V4 Pool of the Liquidity Position.
     * @param poolKey The key containing pool parameters.
     * @param lowerBoundSqrtPrice The minimum acceptable sqrt price after swap (used when swapping token0 for token1).
     * @param upperBoundSqrtPrice The maximum acceptable sqrt price after swap (used when swapping token1 for token0).
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced due to slippage of the swap.
     */
    function _swap(
        PoolKey memory poolKey,
        uint256 lowerBoundSqrtPrice,
        uint256 upperBoundSqrtPrice,
        bool zeroToOne,
        uint256 amountOut
    ) internal returns (bool isPoolUnbalanced_) {
        // Don't do swaps with zero amount.
        if (amountOut == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 = uint160(zeroToOne ? lowerBoundSqrtPrice : upperBoundSqrtPrice);

        // Do the swap.
        bytes memory data = abi.encode(
            IPoolManager.SwapParams({
                zeroForOne: zeroToOne,
                amountSpecified: int256(amountOut),
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            poolKey
        );
        bytes memory results = UniswapV4Logic.POOL_MANAGER.unlock(data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        BalanceDelta swapDelta = abi.decode(results, (BalanceDelta));
        isPoolUnbalanced_ = (amountOut > (zeroToOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0())));
    }

    /**
     * @notice Callback function executed during the unlock phase of a Uniswap V4 swap.
     * @param data The encoded swap parameters and pool key.
     * @return results The encoded BalanceDelta result from the swap operation.
     */
    function unlockCallback(bytes calldata data) external payable onlyPoolManager returns (bytes memory results) {
        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));

        // Do the swap.
        BalanceDelta delta = UniswapV4Logic.POOL_MANAGER.swap(poolKey, params, "");
        results = abi.encode(delta);

        // Processes token balance changes.
        UniswapV4Logic._processSwapDelta(delta, poolKey.currency0, poolKey.currency1);
    }

    /* ///////////////////////////////////////////////////////////////
                        MINTING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds liquidity to a UniswapV4 position.
     * @param poolKey The key containing information about the pool.
     * @param amount0 The amount of token0 to add as liquidity.
     * @param amount1 The amount of token1 to add as liquidity.
     * @param sqrtRatioLower The lower bound of the price range.
     * @param sqrtRatioUpper The upper bound of the price range.
     * @param id The id of the position to add liquidity to.
     */
    function _mint(
        PoolKey memory poolKey,
        uint256 amount0,
        uint256 amount1,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 id
    ) internal {
        // Check it token0 is native ETH.
        bool isNative = Currency.unwrap(poolKey.currency0) == address(0);

        // Handle approvals.
        if (!isNative && amount0 > 0) {
            _checkAndApprovePermit2(Currency.unwrap(poolKey.currency0));
        }
        if (amount1 > 0) _checkAndApprovePermit2(Currency.unwrap(poolKey.currency1));

        // Calculate liquidity to be added.
        (uint160 newSqrtPrice,,,) = UniswapV4Logic.POOL_MANAGER.getSlot0(poolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            newSqrtPrice, uint160(sqrtRatioLower), uint160(sqrtRatioUpper), amount0, amount1
        );

        // Generate calldata to increase liquidity.
        bytes memory actions = new bytes(3);
        actions[0] = bytes1(uint8(Actions.INCREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
        actions[2] = bytes1(uint8(Actions.SWEEP));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(id, liquidity, type(uint128).max, type(uint128).max, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, address(this));

        // Increase the liquidity of the position.
        uint256 ethValue = isNative ? address(this).balance : 0;
        bytes memory increaseLiquidityParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities{ value: ethValue }(increaseLiquidityParams, block.timestamp);
    }

    /* ///////////////////////////////////////////////////////////////
                        PERMIT2 APPROVALS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Ensures that the Permit2 contract has sufficient approval to spend a given token.
     * @param token The contract address of the token.
     */
    function _checkAndApprovePermit2(address token) internal {
        if (!approved[token]) {
            approved[token] = true;
            ERC20(token).safeApproveWithRetry(address(PERMIT_2), type(uint256).max);
            PERMIT_2.approve(token, address(UniswapV4Logic.POSITION_MANAGER), type(uint160).max, type(uint48).max);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    POSITION AND POOL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @param trustedSqrtPrice The pool sqrtPrice provided at the time of calling compoundFees().
     * @param initiator The address of the initiator.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id, uint256 trustedSqrtPrice, address initiator)
        public
        view
        returns (PositionState memory position, PoolKey memory poolKey)
    {
        PositionInfo info;
        (poolKey, info) = UniswapV4Logic.POSITION_MANAGER.getPoolAndPositionInfo(id);

        // Get data of the Liquidity Position.
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(info.tickLower());
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(info.tickUpper());
        (position.sqrtPrice,,,) = UniswapV4Logic.POOL_MANAGER.getSlot0(poolKey.toId());

        // Calculate the upper and lower bounds of sqrtPrice for the Pool to be balanced.
        position.lowerBoundSqrtPrice =
            trustedSqrtPrice.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        position.upperBoundSqrtPrice =
            trustedSqrtPrice.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
    }

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ =
            position.sqrtPrice < position.lowerBoundSqrtPrice || position.sqrtPrice > position.upperBoundSqrtPrice;
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the information requested for an initiator.
     * @param tolerance The maximum deviation of the actual pool price compared to the trustedSqrtPrice provided by the initiator.
     * @param fee The fee paid to the initiator, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPrice for the lower and upper boundaries.
     */
    function setInitiatorInfo(uint256 tolerance, uint256 fee) external {
        if (account != address(0)) revert Reentered();

        // Cache struct
        InitiatorInfo memory initiatorInfo_ = initiatorInfo[msg.sender];

        // Calculation required for checks.
        uint64 upperSqrtPriceDeviation = uint64(FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));

        // Check if initiator is already set.
        if (initiatorInfo_.upperSqrtPriceDeviation > 0) {
            // If so, the initiator can only change parameters to more favourable values for users.
            if (fee > initiatorInfo_.fee || upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation) {
                revert InvalidValue();
            }
        } else {
            // If not, the parameters can not exceed certain thresholds.
            if (fee > MAX_INITIATOR_FEE || tolerance > MAX_TOLERANCE) {
                revert InvalidValue();
            }
        }

        initiatorInfo_.fee = uint64(fee);
        initiatorInfo_.lowerSqrtPriceDeviation = uint64(FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18));
        initiatorInfo_.upperSqrtPriceDeviation = upperSqrtPriceDeviation;

        initiatorInfo[msg.sender] = initiatorInfo_;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets an initiator for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @dev An initiator will be permissioned to compound any
     * Liquidity Position held in the specified Arcadia Account.
     * @dev When an Account is transferred to a new owner,
     * the asset manager itself (this contract) and hence its initiator will no longer be allowed by the Account.
     */
    function setInitiator(address account_, address initiator) external {
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        if (msg.sender != IAccount(account_).owner()) revert OnlyAccountOwner();

        accountToInitiator[account_] = initiator;

        emit InitiatorSet(account_, initiator);
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
