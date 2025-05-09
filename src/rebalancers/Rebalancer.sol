/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IArcadiaFactory } from "./interfaces/IArcadiaFactory.sol";
import { IStrategyHook } from "./interfaces/IStrategyHook.sol";
import { RebalanceLogic, RebalanceParams } from "./libraries/RebalanceLogic.sol";
import { RebalanceOptimizationMath } from "./libraries/RebalanceOptimizationMath.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Abstract Rebalancer for Concentrated Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permisionned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
abstract contract Rebalancer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The maximum deviation of the actual pool price, in % with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
    // It is defined as the quotient between the minimal amount of liquidity that must be added,
    // and the amount of liquidity that would be added if the swap was executed through the pool without slippage.
    // MIN_LIQUIDITY_RATIO = minLiquidity / liquidityWithoutSlippage
    uint256 public immutable MIN_LIQUIDITY_RATIO;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to rebalance the fees for, used as transient storage.
    address internal account;

    // A mapping from initiator to rebalancing fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

    // A mapping that sets the approved initiator per owner per ccount.
    mapping(address owner => mapping(address account => address initiator)) public accountToInitiator;

    // A mapping that sets a strategy hook per account.
    mapping(address account => address hook) public strategyHook;

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 oldId;
        // The amount of token0 withdrawn from the account.
        uint128 amount0;
        // The amount of token1 withdrawn from the account.
        uint128 amount1;
        // The sqrtPrice the pool should have, given by the initiator.
        uint256 trustedSqrtPrice;
        // Calldata provided by the initiator to execute the swap.
        bytes swapData;
        // Strategy specific Calldata provided by the initiator.
        bytes strategyData;
    }

    // A struct with the position and pool state.
    struct PositionState {
        // The contract address of the pool.
        address pool;
        // The id of the position.
        uint256 id;
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

    // A struct with information for each specific initiator.
    struct InitiatorInfo {
        // The maximum relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 upperSqrtPriceDeviation;
        // The miminumù relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 lowerSqrtPriceDeviation;
        // The fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
        uint64 fee;
        // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
        uint64 minLiquidityRatio;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InsufficientLiquidity();
    error InvalidInitiator();
    error InvalidPositionManager();
    error InvalidRouter();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator, address indexed strategyHook);
    event Rebalance(address indexed account, address indexed positionManager, uint256 oldId, uint256 newId);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum fee an initiator can set,
     * relative to the ideal amountIn, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     */
    constructor(address arcadiaFactory, uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        MAX_TOLERANCE = maxTolerance;
        MAX_INITIATOR_FEE = maxInitiatorFee;
        MIN_LIQUIDITY_RATIO = minLiquidityRatio;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param hook The contract address of the hook.
     * @param strategyData Strategy specific data stored in the hook.
     */
    function setAccountInfo(address account_, address initiator, address hook, bytes calldata strategyData) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        accountToInitiator[owner][account_] = initiator;
        strategyHook[account_] = hook;

        IStrategyHook(hook).setStrategy(account_, strategyData);

        emit AccountInfoSet(account_, initiator, hook);
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the information requested for an initiator.
     * @param tolerance The maximum deviation of the actual pool price,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param fee The fee paid to the initiator, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPrice for the lower and upper boundaries.
     */
    function setInitiatorInfo(uint256 tolerance, uint256 fee, uint256 minLiquidityRatio) external {
        if (account != address(0)) revert Reentered();

        // Cache struct
        InitiatorInfo memory initiatorInfo_ = initiatorInfo[msg.sender];

        // Calculation required for checks.
        uint64 upperSqrtPriceDeviation = uint64(FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));

        // Check if initiator is already set.
        if (initiatorInfo_.minLiquidityRatio > 0) {
            // If so, the initiator can only change parameters to more favourable values for users.
            if (
                fee > initiatorInfo_.fee || upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation
                    || minLiquidityRatio < initiatorInfo_.minLiquidityRatio || minLiquidityRatio > 1e18
            ) revert InvalidValue();
        } else {
            // If not, the parameters can not exceed certain thresholds.
            if (
                fee > MAX_INITIATOR_FEE || tolerance > MAX_TOLERANCE || minLiquidityRatio < MIN_LIQUIDITY_RATIO
                    || minLiquidityRatio > 1e18
            ) {
                revert InvalidValue();
            }
        }

        initiatorInfo_.fee = uint64(fee);
        initiatorInfo_.minLiquidityRatio = uint64(minLiquidityRatio);
        initiatorInfo_.lowerSqrtPriceDeviation = uint64(FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18));
        initiatorInfo_.upperSqrtPriceDeviation = upperSqrtPriceDeviation;

        initiatorInfo[msg.sender] = initiatorInfo_;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Rebalances a UniswapV3 or Slipstream Liquidity Position, owned by an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function rebalance(address account_, InitiatorParams calldata initiatorParams) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // If leftovers have to be withdrawn from account, get token0 and token1.
        address token0;
        address token1;
        if (initiatorParams.amount0 > 0 || initiatorParams.amount1 > 0) {
            (token0, token1) = _getUnderlyingTokens(initiatorParams);
        }

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(msg.sender, initiatorParams, token0, token1);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param actionTargetData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in rebalance().
        if (msg.sender != account) revert OnlyAccount();

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));

        // Get all pool and position related state.
        (uint256[] memory balances, PositionState memory position) = _getPositionState(initiatorParams);

        // Call the strategy hook before the rebalance (view function, cannot modify state of pool or old position).
        // The strategy hook will return the new ticks of the position
        // (we override ticks of the memory pointer of the old position as these are no longer needed after this call).
        // Hook can be used to enforce additional strategy specific constraints, specific to the Account/Id.
        // Such as:
        // - Minimum Cool Down Periods.
        // - Excluding rebalancing of certain positions.
        // - ...
        IStrategyHook hook = IStrategyHook(strategyHook[msg.sender]);
        (position.tickLower, position.tickUpper) =
            hook.beforeRebalance(msg.sender, initiatorParams.positionManager, position, initiatorParams.strategyData);

        // Cache variables that are gas expensive to calcultate and used multiple times.
        Cache memory cache = _getCache(initiator, initiatorParams, position);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position, cache)) revert UnbalancedPool();

        // Remove liquidity of the position, claim outstanding fees/rewards and update balances.
        _burn(balances, initiatorParams, position, cache);

        // Get the rebalance parameters, based on a hypothetical swap through the pool itself without slippage.
        RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
            initiatorInfo[initiator].minLiquidityRatio,
            position.fee,
            initiatorInfo[initiator].fee,
            position.sqrtPrice,
            cache.sqrtRatioLower,
            cache.sqrtRatioUpper,
            balances[0],
            balances[1]
        );

        // Do the swap to rebalance the position.
        // This can be done either directly through the pool, or via a router with custom swap data.
        // For swaps directly through the pool, if slippage is bigger than calculated, the transaction will not immediately revert,
        // but excess slippage will be subtracted from the initiatorFee.
        // For swaps via a router, tokenOut should be the limiting factor when increasing liquidity.
        // Update balances after the swap.
        _swap(balances, initiatorParams, position, rebalanceParams, cache);

        // Check that the pool is still balanced after the swap.
        if (isPoolUnbalanced(position, cache)) revert UnbalancedPool();

        // Mint the new liquidity position.
        // We mint with the total available balances of token0 and token1, not subtracting the initiator fee.
        // Leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
        // and the initiator fee will be 0 (but the transaction will not revert).
        // Update balances after the mint.
        _mint(balances, initiatorParams, position, cache);

        // Check that the actual liquidity of the position is above the minimum threshold.
        // This prevents loss of principal of the liquidity position due to slippage,
        // or malicious initiators who remove liquidity during a custom swap.
        if (position.liquidity < rebalanceParams.minLiquidity) revert InsufficientLiquidity();

        // Call the strategy hook after the rebalance (non view function).
        // Can be used to check additional constraints and persist state changes on the hook.
        hook.afterRebalance(
            msg.sender, initiatorParams.positionManager, initiatorParams.oldId, position, initiatorParams.strategyData
        );

        // Transfer fee to the initiator and update balances.
        _transferInitiatorFee(
            balances, position, rebalanceParams.zeroToOne, rebalanceParams.amountInitiatorFee, initiator
        );

        // Approve assets to deposit them back into the Account.
        uint256 count = _approve(balances, initiatorParams, position);

        // Encode deposit data for the flash-action.
        depositData =
            ArcadiaLogic._encodeDeposit(initiatorParams.positionManager, position.id, count, position.tokens, balances);

        emit Rebalance(msg.sender, initiatorParams.positionManager, initiatorParams.oldId, position.id);
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
     * @notice Returns the underlying assets of the pool.
     * @param initiatorParams A struct with the initiator parameters.
     * @return token0 The contract address of token0.
     * @return token1 The contract address of token1.
     */
    function _getUnderlyingTokens(InitiatorParams memory initiatorParams)
        internal
        view
        virtual
        returns (address token0, address token1);

    /**
     * @notice Returns the position and pool related state.
     * @param initiatorParams A struct with the initiator parameters.
     * @return balances The balances of the underlying tokens of the position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(InitiatorParams memory initiatorParams)
        internal
        view
        virtual
        returns (uint256[] memory balances, PositionState memory position);

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

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(PositionState memory position) internal view virtual returns (uint128 liquidity);

    /**
     * @notice Returns the sqrtPrice of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPrice The sqrtPrice of the Pool.
     */
    function _getSqrtPrice(PositionState memory position) internal view virtual returns (uint160 sqrtPrice);

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @dev Must update the balances after the burn.
     */
    function _burn(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param rebalanceParams A struct with the rebalance parameters.
     * @param cache A struct with cached variables.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _swap(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Cache memory cache
    ) internal virtual {
        // Don't do swaps with zero amount.
        if (rebalanceParams.amountIn == 0) return;

        // Do the actual swap to rebalance the position.
        // This can be done either directly through the pool, or via a router with custom swap data.
        if (initiatorParams.swapData.length == 0) {
            // Calculate a more accurate amountOut, with slippage.
            uint256 amountOut = RebalanceOptimizationMath._getAmountOutWithSlippage(
                rebalanceParams.zeroToOne,
                position.fee,
                _getPoolLiquidity(position),
                uint160(position.sqrtPrice),
                cache.sqrtRatioLower,
                cache.sqrtRatioUpper,
                rebalanceParams.zeroToOne ? balances[0] - rebalanceParams.amountInitiatorFee : balances[0],
                rebalanceParams.zeroToOne ? balances[1] : balances[1] - rebalanceParams.amountInitiatorFee,
                rebalanceParams.amountIn,
                rebalanceParams.amountOut
            );
            // Don't do swaps with zero amount.
            if (amountOut == 0) return;
            _swapViaPool(balances, position, cache, rebalanceParams.zeroToOne, amountOut);
        } else {
            _swapViaRouter(balances, position, rebalanceParams.zeroToOne, initiatorParams.swapData);
        }
    }

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

    /**
     * @notice Swaps one token for another, via a router with custom swap data.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @dev Initiator has to route swap in such a way that at least minLiquidity of liquidity is added to the position after the swap.
     * And leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
     * and the initiator fee will be 0 (but the transaction will not revert)
     */
    function _swapViaRouter(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal virtual {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));
        if (router == strategyHook[msg.sender]) revert InvalidRouter();

        // Approve token to swap.
        ERC20(zeroToOne ? position.tokens[0] : position.tokens[1]).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPrice might have moved and brought the pool out of balance.
        // By fetching the sqrtPrice, the transaction will revert in that case on the balance check.
        position.sqrtPrice = _getSqrtPrice(position);

        // Update the balances.
        balances[0] = ERC20(position.tokens[0]).balanceOf(address(this));
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     * @dev Must update the balances and liquidity and id after the mint.
     */
    function _mint(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                        INITIATOR FEE LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Transfers the initiator fee to the initiator.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 was swapped to token1 or opposite.
     * @param amountInitiatorFee The amount of initiator fee.
     * @param initiator The address of the initiator.
     * @dev Must update the balances after the transfer.
     */
    function _transferInitiatorFee(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        address initiator
    ) internal virtual {
        if (zeroToOne) {
            (balances[0], amountInitiatorFee) = balances[0] > amountInitiatorFee
                ? (balances[0] - amountInitiatorFee, amountInitiatorFee)
                : (0, balances[0]);
            if (amountInitiatorFee > 0) {
                ERC20(position.tokens[0]).safeTransfer(initiator, amountInitiatorFee);
            }
        } else {
            (balances[1], amountInitiatorFee) = balances[1] > amountInitiatorFee
                ? (balances[1] - amountInitiatorFee, amountInitiatorFee)
                : (0, balances[1]);
            if (amountInitiatorFee > 0) {
                ERC20(position.tokens[1]).safeTransfer(initiator, amountInitiatorFee);
            }
        }
    }

    /* ///////////////////////////////////////////////////////////////
                        APPROVE LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Approves the Account to deposit the assets held by the Rebalancer back into the Account.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @return count The number of assets approved.
     */
    function _approve(uint256[] memory balances, InitiatorParams memory initiatorParams, PositionState memory position)
        internal
        returns (uint256 count)
    {
        // Approve the Liquidity Position.
        ERC721(initiatorParams.positionManager).approve(msg.sender, position.id);

        // Approve the ERC20 yield tokens.
        count = 1;
        // Approve Account to redeposit Liquidity Position and leftovers.
        for (uint256 i; i < balances.length; i++) {
            if (balances[i] > 0) {
                ERC20(position.tokens[i]).safeApproveWithRetry(msg.sender, balances[i]);
                count++;
            }
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
                      NATIVE ETH HANDLER
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Receives native ether.
     */
    receive() external payable { }
}
