/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { BalanceDelta } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IHooks } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { IPool } from "./interfaces/IPool.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IStrategyHook } from "./interfaces/IStrategyHook.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { LiquidityAmounts } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { MintLogic } from "./libraries/shared-uniswap-v3-slipstream/MintLogic.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PricingLogic } from "./libraries/cl-math/PricingLogic.sol";
import { RebalanceLogic } from "./libraries/RebalanceLogic.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";
import { SafeApprove } from "./libraries/SafeApprove.sol";
import { SlipstreamLogic } from "./libraries/slipstream/SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./libraries/slipstream/StakedSlipstreamLogic.sol";
import { SwapLogicV4 } from "./libraries/uniswap-v4/SwapLogicV4.sol";
import { SwapParams } from "./interfaces/IPoolManager.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4Logic } from "./libraries/uniswap-v4/UniswapV4Logic.sol";

/**
 * @title Permissioned rebalancer for Uniswap V4 Positions.
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
contract RebalancerUniswapV4 is ReentrancyGuard, IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // keccak256("RebalancerUniswapV4Account")
    bytes32 internal constant ACCOUNT_SLOT = 0x77a1096cdeeb44155ee048b1ea572763589db8a085320c2033ef421fb1ea0fd9;
    // keccak256("RebalancerUniswapV4TrustedSqrtPriceX96")
    bytes32 internal constant TRUSTED_SQRT_PRICE_X96_SLOT =
        0x6812d077d53d77b2024c92449df504697e32036eb13236495d0c94a4f1ddc1e6;
    // The contract address of WETH.
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // The maximum deviation of the actual pool price, in % with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
    // It is defined as the quotient between the minimal amount of liquidity that must be added,
    // and the amount of liquidity that would be added if the swap was executed through the pool without slippage.
    // MIN_LIQUIDITY_RATIO = minLiquidity / liquidityWithoutSlippage
    uint256 public immutable MIN_LIQUIDITY_RATIO;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from initiator to rebalancing fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

    // A mapping that sets the approved initiator per account.
    mapping(address account => address initiator) public accountToInitiator;

    // A mapping that sets a strategy hook per account.
    mapping(address account => address hook) public strategyHook;

    // A struct with the state of a specific position, only used in memory.
    struct PositionState {
        address hook;
        address token0;
        address token1;
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

    // A struct with information for each specific initiator
    struct InitiatorInfo {
        uint64 upperSqrtPriceDeviation;
        uint64 lowerSqrtPriceDeviation;
        uint64 fee;
        uint64 minLiquidityRatio;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InitiatorNotValid();
    error InsufficientLiquidity();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyPool();
    error OnlyPoolManager();
    error PoolManagerOnly();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator, address indexed strategyHook);
    event Rebalance(address indexed account, address indexed positionManager, uint256 oldId, uint256 newId);

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
     * @param maxInitiatorFee The maximum fee an initiator can set,
     * relative to the ideal amountIn, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     */
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio) {
        MAX_TOLERANCE = maxTolerance;
        MAX_INITIATOR_FEE = maxInitiatorFee;
        MIN_LIQUIDITY_RATIO = minLiquidityRatio;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Rebalances a Uniswap V4 or Slipstream Liquidity Position, owned by an Arcadia Account.
     * @param account The Arcadia Account owning the position.
     * @param positionManager The contract address of the Position Manager.
     * @param oldId The oldId of the Liquidity Position to rebalance.
     * @param trustedSqrtPriceX96 The pool sqrtPriceX96 provided at the time of calling rebalance().
     * @param tickLower The new lower tick to rebalance to.
     * @param tickUpper The new upper tick to rebalance to.
     * @dev When tickLower and tickUpper are equal, ticks will be updated with same tick-spacing as current position
     * and with a balanced, 50/50 ratio around current tick.
     */
    function rebalance(
        address account,
        address positionManager,
        uint256 oldId,
        uint256 trustedSqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) external nonReentrant {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (accountToInitiator[account] != msg.sender) revert InitiatorNotValid();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        assembly {
            tstore(ACCOUNT_SLOT, account)
            tstore(TRUSTED_SQRT_PRICE_X96_SLOT, trustedSqrtPriceX96)
        }

        // Encode data for the flash-action.
        bytes memory actionData =
            ArcadiaLogic._encodeAction(positionManager, oldId, msg.sender, tickLower, tickUpper, swapData);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account).flashAction(address(this), actionData);
    }

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param rebalanceData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata rebalanceData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in rebalance().
        address account;
        assembly {
            account := tload(ACCOUNT_SLOT)
        }

        if (msg.sender != account) revert OnlyAccount();

        // Cache the strategy hook.
        address hook = strategyHook[msg.sender];

        // Decode rebalanceData.
        bytes memory swapData;
        address positionManager;
        uint256 oldId;
        uint256 newId;
        PositionState memory position;
        address initiator;
        {
            ActionData memory assetData;
            int24 tickLower;
            int24 tickUpper;
            (assetData, initiator, tickLower, tickUpper, swapData) =
                abi.decode(rebalanceData, (ActionData, address, int24, int24, bytes));
            positionManager = assetData.assets[0];
            oldId = assetData.assetIds[0];

            // Fetch and cache all position related data.
            position = getPositionState(oldId, tickLower, tickUpper, initiator);
        }

        // If set, call the strategy hook before the rebalance (view function).
        // This can be used to enforce additional constraints on the rebalance, specific to the Account/Id.
        // Such as:
        // - Directional preferences.
        // - Minimum Cool Down Periods.
        // - Excluding rebalancing of certain positions.
        // - ...
        if (hook != address(0)) {
            IStrategyHook(hook).beforeRebalance(
                msg.sender, positionManager, oldId, position.tickLower, position.tickUpper
            );
        }

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Remove liquidity of the position and claim outstanding fees/rewards.
        (uint256 balance0, uint256 balance1) = _burn(oldId, position.token0, position.token1);

        {
            // Get the rebalance parameters.
            // These are calculated based on a hypothetical swap through the pool, without slippage.
            (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut) =
            RebalanceLogic._getRebalanceParams(
                initiatorInfo[initiator].minLiquidityRatio,
                position.fee,
                initiatorInfo[initiator].fee,
                position.sqrtPriceX96,
                position.sqrtRatioLower,
                position.sqrtRatioUpper,
                balance0,
                balance1
            );

            PoolKey memory poolKey = PoolKey(
                Currency.wrap(position.token0),
                Currency.wrap(position.token1),
                position.fee,
                position.tickSpacing,
                IHooks(position.hook)
            );
            // Do the actual swap to rebalance the position.
            // This can be done either directly through the pool, or via a router with custom swap data.
            // For swaps directly through the pool, if slippage is bigger than calculated, the transaction will not immediately revert,
            // but excess slippage will be subtracted from the initiatorFee.
            // For swaps via a router, tokenOut should be the limiting factor when increasing liquidity.
            (balance0, balance1) = SwapLogicV4._swap(
                swapData, position, poolKey, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
            );

            // Check that the pool is still balanced after the swap.
            if (isPoolUnbalanced(position)) revert UnbalancedPool();

            // Mint the new liquidity position.
            // We mint with the total available balances of token0 and token1, not subtracting the initiator fee.
            // Leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
            // and the initiator fee will be 0 (but the transaction will not revert).
            uint256 liquidity;
            (newId, liquidity, balance0, balance1) = _mint(position, poolKey, balance0, balance1);

            // Check that the actual liquidity of the position is above the minimum threshold.
            // This prevents loss of principal of the liquidity position due to slippage,
            // or malicious initiators who remove liquidity during a custom swap.
            if (liquidity < minLiquidity) revert InsufficientLiquidity();

            // Transfer fee to the initiator.
            (balance0, balance1) = _transferFee(
                initiator, zeroToOne, amountInitiatorFee, position.token0, position.token1, balance0, balance1
            );
        }

        // Approve Account to redeposit Liquidity Position and leftovers.
        {
            uint256 count = 1;
            IPositionManager(positionManager).approve(msg.sender, newId);

            // If leftover is in native ETH, we need to wrap it and send WETH to the Account.
            if (position.token0 == address(0)) position.token0 = WETH;
            if (position.token1 == address(0)) position.token1 = WETH;

            if (balance0 > 0) {
                ERC20(position.token0).safeApproveWithRetry(msg.sender, balance0);
                count = 2;
            }
            if (balance1 > 0) {
                ERC20(position.token1).safeApproveWithRetry(msg.sender, balance1);
                ++count;
            }

            // Encode deposit data for the flash-action.
            depositData = ArcadiaLogic._encodeDeposit(
                positionManager, newId, position.token0, position.token1, count, balance0, balance1, 0
            );
        }

        // If set, call the strategy hook after the rebalance (non view function).
        // Can be used to check additional constraints and persist state changes on the hook.
        if (hook != address(0)) IStrategyHook(hook).afterRebalance(msg.sender, positionManager, oldId, newId);

        emit Rebalance(msg.sender, positionManager, oldId, newId);

        return depositData;
    }

    /* ///////////////////////////////////////////////////////////////
                          UNISWAP V4 LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @dev Mints a new Uniswap V4 position by providing liquidity to a specified pool.
     * @param position The memory struct containing details about the state of the Uniswap position.
     * @param balance0 The amount of token0 to be added to the position.
     * @param balance1 The amount of token1 to be added to the position.
     * @return newTokenId The ID of the newly minted Uniswap V4 position.
     * @return liquidity The calculated liquidity corresponding to the provided balances and ticks.
     * @return balance0_ The final amount of token0 used in the minting process.
     * @return balance1_ The final amount of token1 used in the minting process.
     */
    function _mint(PositionState memory position, PoolKey memory poolKey, uint256 balance0, uint256 balance1)
        internal
        returns (uint256 newTokenId, uint256 liquidity, uint256 balance0_, uint256 balance1_)
    {
        // Manage token approvals and check if native ETH has to be added to the position.
        if (position.token0 != address(0)) UniswapV4Logic._checkAndApprovePermit2(position.token0, balance0);
        if (position.token1 != address(0)) UniswapV4Logic._checkAndApprovePermit2(position.token1, balance1);

        // Generate calldata to mint new position.
        bytes[] memory params = new bytes[](2);
        {
            (uint160 newSqrtPriceX96,,,) = UniswapV4Logic.STATE_VIEW.getSlot0(poolKey.toId());
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                newSqrtPriceX96, position.sqrtRatioLower, position.sqrtRatioUpper, balance0, balance1
            );

            params[0] = abi.encode(
                poolKey,
                position.tickLower,
                position.tickUpper,
                liquidity,
                type(uint128).max,
                type(uint128).max,
                address(this),
                ""
            );
            params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        }

        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(UniswapV4Logic.MINT_POSITION));
        actions[1] = bytes1(uint8(UniswapV4Logic.SETTLE_PAIR));

        // Get new token id.
        newTokenId = UniswapV4Logic.POSITION_MANAGER.nextTokenId();

        // Mint the new position.
        uint256 ethValue =
            (position.token0 == address(0) ? balance0 : 0) + (position.token1 == address(0) ? balance1 : 0);
        bytes memory mintParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities{ value: ethValue }(mintParams, block.timestamp);

        // As UniswapV4 works with specific liquidity, there should be no leftovers.
        // Note : To Confirm. (in tests-)
        balance0_ = 0;
        balance1_ = 0;
    }

    /**
     * @dev Burns a Uniswap V4 position, removing liquidity and collecting the underlying assets.
     * @param id The id of the Uniswap V4 position to burn.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @return balance0 The amount of token0 received after burning the position.
     * @return balance1 The amount of token1 received after burning the position.
     */
    function _burn(uint256 id, address token0, address token1) internal returns (uint256 balance0, uint256 balance1) {
        // Generate calldata to burn the position and collect the underlying assets.
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(UniswapV4Logic.BURN_POSITION));
        actions[1] = bytes1(uint8(UniswapV4Logic.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);
        params[0] = abi.encode(id, 0, 0, "");
        params[1] = abi.encode(currency0, currency1, address(this));

        // Cache init balance of token0 and token1.
        uint256 initBalanceCurrency0 = currency0.balanceOfSelf();
        uint256 initBalanceCurrency1 = currency1.balanceOfSelf();

        bytes memory burnParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities(burnParams, block.timestamp);

        balance0 = currency0.balanceOfSelf() - initBalanceCurrency0;
        balance1 = currency1.balanceOfSelf() - initBalanceCurrency1;
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
     * @param oldId The oldId of the Liquidity Position.
     * @param tickLower The lower tick of the newly minted position.
     * @param tickUpper The upper tick of the newly minted position.
     * @param initiator The address of the initiator.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 oldId, int24 tickLower, int24 tickUpper, address initiator)
        public
        view
        virtual
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        (int24 tickCurrent, int24 tickRange) = UniswapV4Logic._getPositionState(position, oldId);

        // Store the new ticks for the rebalance
        if (tickLower == tickUpper) {
            // Round current tick down to a tick that is a multiple of the tick spacing (can be initialised).
            // We do not handle the edge cases where the new ticks might exceed MIN_TICK or MAX_TICK.
            // This will result in a revert during the mint, if ever needed a different rebalancer has to be deployed.
            tickCurrent = tickCurrent / position.tickSpacing * position.tickSpacing;
            // For tick ranges that are an even multiple of the tick spacing, we use a symmetric spacing around the current tick.
            // For uneven multiples, the smaller part is below the current tick.
            position.tickLower = tickCurrent - tickRange / (2 * position.tickSpacing) * position.tickSpacing;
            position.tickUpper = position.tickLower + tickRange;
        } else {
            (position.tickLower, position.tickUpper) = (tickLower, tickUpper);
        }
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        // We do not handle the edge cases where exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        uint256 trustedSqrtPriceX96;
        assembly {
            trustedSqrtPriceX96 := tload(TRUSTED_SQRT_PRICE_X96_SLOT)
        }

        position.lowerBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        position.upperBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */
    /**
     * @notice Sets the required information for an Account.
     * @param account The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param hook The contract address of the hook.
     * @dev An initiator will be permissioned to rebalance any
     * Liquidity Position held in the specified Arcadia Account.
     * @dev If the hook is set to address(0), the hook will be disabled.
     * @dev When an Account is transferred to a new owner,
     * the asset manager itself (this contract) and hence its initiator and hook will no longer be allowed by the Account.
     */
    function setAccountInfo(address account, address initiator, address hook) external nonReentrant {
        if (!ArcadiaLogic.FACTORY.isAccount(account)) revert NotAnAccount();
        if (msg.sender != IAccount(account).owner()) revert OnlyAccountOwner();

        accountToInitiator[account] = initiator;
        strategyHook[account] = hook;

        emit AccountInfoSet(account, initiator, hook);
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
    function setInitiatorInfo(uint256 tolerance, uint256 fee, uint256 minLiquidityRatio) external nonReentrant {
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

    /**
     * @notice Transfers the initiator fee to the initiator.
     * @param initiator The address of the initiator.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountInitiatorFee The amount of initiator fee.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param balance0 The balance of token0 before transferring the initiator fee.
     * @param balance1 The balance of token1 before transferring the initiator fee.
     * @return balance0 The balance of token0 after transferring the initiator fee.
     * @return balance1 The balance of token1 after transferring the initiator fee.
     */
    function _transferFee(
        address initiator,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256, uint256) {
        unchecked {
            if (zeroToOne) {
                (balance0, amountInitiatorFee) =
                    balance0 > amountInitiatorFee ? (balance0 - amountInitiatorFee, amountInitiatorFee) : (0, balance0);
                if (amountInitiatorFee > 0) Currency.wrap(token0).transfer(initiator, amountInitiatorFee);
            } else {
                (balance1, amountInitiatorFee) =
                    balance1 > amountInitiatorFee ? (balance1 - amountInitiatorFee, amountInitiatorFee) : (0, balance1);
                if (amountInitiatorFee > 0) Currency.wrap(token1).transfer(initiator, amountInitiatorFee);
            }
            return (balance0, balance1);
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
     * @dev Required since the Slipstream Non Fungible Position Manager sends full ether balance to caller
     * on an increaseLiquidity.
     * @dev Funds received can not be reclaimed, the receive only serves as a protection against griefing attacks.
     */
    receive() external payable {
        if (msg.sender != address(UniswapV4Logic.POOL_MANAGER)) revert OnlyPoolManager();
    }
}
