/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic2.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IArcadiaFactory } from "./interfaces/IArcadiaFactory.sol";
import { IStrategyHook } from "./interfaces/IStrategyHook.sol";
import { RebalanceLogic, RebalanceParams } from "./libraries/RebalanceLogic2.sol";
import { RebalanceOptimizationMath } from "./libraries/RebalanceOptimizationMath.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Permissioned rebalancer for Uniswap V3 and Slipstream Liquidity Positions.
 * @notice The Rebalancer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permisionned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPriceX96 input at the time of rebalance to mitigate frontrunning risks.
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

    // A mapping that sets the approved initiator per account.
    mapping(address account => address initiator) public accountToInitiator;

    // A mapping that sets a strategy hook per account.
    mapping(address account => address hook) public strategyHook;

    struct InitiatorParams {
        address positionManager;
        uint96 oldId;
        uint128 amount0;
        uint128 amount1;
        uint256 trustedSqrtPriceX96;
        bytes swapData;
        bytes strategyData;
    }

    struct PositionState {
        address pool;
        uint256 id;
        uint24 fee;
        int24 tickSpacing;
        int24 tickCurrent;
        int24 tickUpper;
        int24 tickLower;
        uint128 liquidity;
        uint256 sqrtPriceX96;
        address[] tokens;
    }

    struct Cache {
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
        uint160 sqrtRatioLower;
        uint160 sqrtRatioUpper;
    }

    // A struct with information for each specific initiator.
    struct InitiatorInfo {
        uint64 upperSqrtPriceDeviation;
        uint64 lowerSqrtPriceDeviation;
        uint64 fee;
        uint64 minLiquidityRatio;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InsufficientLiquidity();
    error InvalidInitiator();
    error InvalidPositionManager();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyPositionManager();
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
     * @dev An initiator will be permissioned to rebalance any
     * Liquidity Position held in the specified Arcadia Account.
     * @dev If the hook is set to address(0), the hook will be disabled.
     * @dev When an Account is transferred to a new owner,
     * the asset manager itself (this contract) and hence its initiator and hook will no longer be allowed by the Account.
     */
    function setAccountInfo(address account_, address initiator, address hook, bytes calldata strategyData) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        if (msg.sender != IAccount(account_).owner()) revert OnlyAccountOwner();

        accountToInitiator[account_] = initiator;
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
     * allowed deviation of the sqrtPriceX96 for the lower and upper boundaries.
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
     * @dev When tickLower and tickUpper are equal, ticks will be updated with same tick-spacing as current position
     * and with a balanced, 50/50 ratio around current tick.
     */
    function rebalance(address account_, InitiatorParams calldata initiatorParams) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InvalidInitiator();
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

        // Cache variables that are gas expensive to calcultate and used multiple times.
        Cache memory cache = _getCache(initiator, initiatorParams, position);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position, cache)) revert UnbalancedPool();

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

        // Remove liquidity of the position, claim outstanding fees/rewards and update balances.
        _burn(balances, initiatorParams, position, cache);

        // Get the rebalance parameters, based on a hypothetical swap through the pool itself without slippage.
        RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
            initiatorInfo[initiator].minLiquidityRatio,
            position.fee,
            initiatorInfo[initiator].fee,
            position.sqrtPriceX96,
            cache.sqrtRatioLower,
            cache.sqrtRatioUpper,
            balances[0],
            balances[1]
        );

        // Do the actual swap to rebalance the position.
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

        // Transfer fee to the initiator.
        // Update balances after the transfer.
        _transferInitiatorFee(
            balances, position, rebalanceParams.zeroToOne, rebalanceParams.amountInitiatorFee, initiator
        );

        // Approve assets to deposit them back into the Account.
        uint256 count = _approve(balances, initiatorParams, position);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(
            initiatorParams.positionManager, initiatorParams.oldId, count, position.tokens, balances
        );

        emit Rebalance(msg.sender, initiatorParams.positionManager, initiatorParams.oldId, position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    function isPositionManager(address positionManager) public view virtual returns (bool);

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position, Cache memory cache)
        public
        pure
        returns (bool isPoolUnbalanced_)
    {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ = position.sqrtPriceX96 <= cache.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 >= cache.upperBoundSqrtPriceX96;
    }

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    function _getCache(address initiator, InitiatorParams memory initiatorParams, PositionState memory position)
        internal
        view
        virtual
        returns (Cache memory cache)
    {
        // We do not handle the edge cases where the bounds of the sqrtPriceX96 exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        cache = Cache({
            lowerBoundSqrtPriceX96: initiatorParams.trustedSqrtPriceX96.mulDivDown(
                initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18
            ),
            upperBoundSqrtPriceX96: initiatorParams.trustedSqrtPriceX96.mulDivDown(
                initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18
            ),
            sqrtRatioLower: TickMath.getSqrtPriceAtTick(position.tickLower),
            sqrtRatioUpper: TickMath.getSqrtPriceAtTick(position.tickUpper)
        });
    }

    function _getUnderlyingTokens(InitiatorParams memory initiatorParams)
        internal
        view
        virtual
        returns (address token0, address token1);

    function _getPositionState(InitiatorParams memory initiatorParams)
        internal
        view
        virtual
        returns (uint256[] memory balances, PositionState memory);

    function _getPoolLiquidity(PositionState memory position) internal view virtual returns (uint128);

    function _getSqrtPriceX96(PositionState memory position) internal view virtual returns (uint160);

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    function _burn(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

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
                uint160(position.sqrtPriceX96),
                cache.sqrtRatioLower,
                cache.sqrtRatioUpper,
                rebalanceParams.zeroToOne ? balances[0] - rebalanceParams.amountInitiatorFee : balances[0],
                rebalanceParams.zeroToOne ? balances[1] : balances[1] - rebalanceParams.amountInitiatorFee,
                rebalanceParams.amountIn,
                rebalanceParams.amountOut
            );
            // Don't do swaps with zero amount.
            if (amountOut == 0) return;
            _swapViaPool(balances, position, rebalanceParams, cache, amountOut);
        } else {
            _swapViaRouter(balances, position, rebalanceParams.zeroToOne, initiatorParams.swapData);
        }
    }

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     */
    function _swapViaPool(
        uint256[] memory balances,
        PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Cache memory cache,
        uint256 amountOut
    ) internal virtual;

    /**
     * @notice Swaps one token for another, directly through the pool itself.
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
    ) internal {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

        // Approve token to swap.
        ERC20(zeroToOne ? position.tokens[0] : position.tokens[1]).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPriceX96 might have moved and brought the pool out of balance.
        // By fetching the sqrtPriceX96, the transaction will revert in that case on the balance check.
        position.sqrtPriceX96 = _getSqrtPriceX96(position);

        // Update the balances.
        balances[0] = ERC20(position.tokens[0]).balanceOf(address(this));
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    function _mint(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                        INITIATOR FEE LOGIC
    /////////////////////////////////////////////////////////////// */

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
