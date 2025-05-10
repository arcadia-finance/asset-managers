/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic2.sol";
import { CLMath } from "../libraries/CLMath.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Abstract Compounder for Concentrated Liquidity Positions.
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
abstract contract Compounder is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IFactory public immutable ARCADIA_FACTORY;

    // The maximum deviation of the actual pool price copared the price given by the initiator, with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to compound the fees for, used as transient storage.
    address internal account;

    // A mapping from initiator to a struct with initiator-specific tolerance and fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

    // A mapping that sets the approved initiator per owner per ccount.
    mapping(address owner => mapping(address account => address initiator)) public accountToInitiator;

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 id;
        // The sqrtPrice the pool should have, given by the initiator.
        uint256 trustedSqrtPrice;
    }

    // A struct with the position and pool state.
    struct PositionState {
        // The contract address of the pool.
        address pool;
        // The fee of the pool
        uint24 fee;
        // The tickspacing of the pool.
        int24 tickSpacing;
        // The current tick of the pool.
        int24 tickCurrent;
        // The lower tick of the position.
        int24 tickUpper;
        // The upper tick of the position.
        int24 tickLower;
        // The liquidity of the position.
        uint128 liquidity;
        // The sqrtPrice of the pool.
        uint256 sqrtPrice;
        // The underlying tokens of the pool.
        address[] tokens;
    }

    // A struct with cached variables.
    struct Cache {
        // The lower bound the sqrtPrice can have for the pool to be balanced.
        uint256 lowerBoundSqrtPrice;
        // The lower bound the sqrtPrice can have for the pool to be balanced.
        uint256 upperBoundSqrtPrice;
        // The sqrtRatio of the lower tick.
        uint160 sqrtRatioLower;
        // The sqrtRatio of the upper tick.
        uint160 sqrtRatioUpper;
        // Implementation specific data.
        bytes data;
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

    error InvalidInitiator();
    error InvalidPositionManager();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Compound(address indexed account, uint256 id);
    event InitiatorSet(address indexed account, address indexed initiator);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum initiator fee an initiator can set.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPrice for the lower and upper boundaries.
     */
    constructor(address arcadiaFactory, uint256 maxTolerance, uint256 maxInitiatorFee) {
        ARCADIA_FACTORY = IFactory(arcadiaFactory);
        MAX_INITIATOR_FEE = maxInitiatorFee;
        MAX_TOLERANCE = maxTolerance;
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
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        accountToInitiator[owner][account_] = initiator;

        emit InitiatorSet(account_, initiator);
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
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Compounds the fees earned by a UniswapV3 Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function compound(address account_, InitiatorParams calldata initiatorParams) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeActionData(msg.sender, initiatorParams);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param actionTargetData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the asset data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Verify that the pool's current price is initially within the defined tolerance price range.
     * - Collects the fees earned by the position.
     * - Rebalance the fee amounts so that the maximum amount of liquidity can be added, swaps one token to another if needed.
     * - Verify that the pool's price is still within the defined tolerance price range after the swap.
     * - Increases the liquidity of the current position with those fees.
     * - Transfers initiator fees to the initiator.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in compoundFees().
        if (msg.sender != account) revert OnlyAccount();

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));

        // Fetch and cache all position related data.
        PositionState memory position = _getPositionState(initiatorParams);

        // Cache variables that are gas expensive to calcultate and used multiple times.
        Cache memory cache = _getCache(initiator, initiatorParams, position);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position, cache)) revert UnbalancedPool();

        // Collect fees and update balances.
        uint256[] memory balances = new uint256[](2);
        _claim(balances, initiatorParams, position, cache);

        // Subtract initiator fee from claimed fees, these will be send to the initiator.
        uint256 initiatorFee = initiatorInfo[initiator].fee;
        uint256[] memory initiatorFees = new uint256[](2);
        initiatorFees[0] = balances[0].mulDivDown(initiatorFee, 1e18);
        initiatorFees[1] = balances[1].mulDivDown(initiatorFee, 1e18);

        // Calculate the swap parameters.
        (bool zeroToOne,, uint256 amountOut) = CLMath._getSwapParams(
            position.sqrtPrice,
            cache.sqrtRatioLower,
            cache.sqrtRatioUpper,
            balances[0] - initiatorFees[0],
            balances[1] - initiatorFees[1],
            position.fee
        );

        // Do the swap to rebalance the fees and update balances.
        _swapViaPool(balances, position, cache, zeroToOne, amountOut);

        // Check that the pool is still balanced after the swap.
        if (isPoolUnbalanced(position, cache)) revert UnbalancedPool();

        // Increase liquidity of the liquidity position.
        // We only subtract the initiator fee from the amountOut, not from the amountIn.
        // This guarantees that tokenOut is the limiting factor when increasing liquidity and not tokenIn.
        // As a consequence, slippage will result in less tokenIn going to the initiator,
        // instead of more tokenOut going to the initiator.
        // Update balances after the increasing liquidity.
        (uint256 amount0Desired, uint256 amount1Desired) =
            zeroToOne ? (balances[0], balances[1] - initiatorFees[1]) : (balances[0] - initiatorFees[0], balances[1]);
        _increaseLiquidity(balances, initiatorParams, position, cache, amount0Desired, amount1Desired);

        // Transfer initiator fees to the initiator.
        if (balances[0] > 0) ERC20(position.tokens[0]).safeTransfer(initiator, balances[0]);
        if (balances[1] > 0) ERC20(position.tokens[1]).safeTransfer(initiator, balances[1]);

        // Approve the Liquidity Position.
        ERC721(initiatorParams.positionManager).approve(msg.sender, initiatorParams.id);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(initiatorParams);

        emit Compound(msg.sender, initiatorParams.id);
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the rebalancer.
     * @param positionManager the contract address of the position manager to check.
     */
    function isPositionManager(address positionManager) public view virtual returns (bool);

    /**
     * @notice Returns if the pool of a Liquidity Position is unbalanced.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position, Cache memory cache)
        public
        pure
        returns (bool isPoolUnbalanced_)
    {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ =
            position.sqrtPrice <= cache.lowerBoundSqrtPrice || position.sqrtPrice >= cache.upperBoundSqrtPrice;
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
        virtual
        returns (PositionState memory position);

    /**
     * @notice Returns the cached variables.
     * @param initiator The address of the initiator.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @return cache A struct with cached variables.
     */
    function _getCache(address initiator, InitiatorParams memory initiatorParams, PositionState memory position)
        internal
        view
        virtual
        returns (Cache memory cache)
    {
        // We do not handle the edge cases where the bounds of the sqrtPrice exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        cache = Cache({
            lowerBoundSqrtPrice: initiatorParams.trustedSqrtPrice.mulDivDown(
                initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18
            ),
            upperBoundSqrtPrice: initiatorParams.trustedSqrtPrice.mulDivDown(
                initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18
            ),
            sqrtRatioLower: TickMath.getSqrtPriceAtTick(position.tickLower),
            sqrtRatioUpper: TickMath.getSqrtPriceAtTick(position.tickUpper),
            data: ""
        });
    }

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @dev Must update the balances after the claim.
     */
    function _claim(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                            SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _swapViaPool(
        uint256[] memory balances,
        PositionState memory position,
        Cache memory cache,
        bool zeroToOne,
        uint256 amountOut
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual;

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
                      NATIVE ETH HANDLER
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Receives native ether.
     */
    receive() external payable { }
}
