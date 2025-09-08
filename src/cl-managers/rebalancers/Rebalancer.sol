/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../base/AbstractBase.sol";
import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../../guardian/Guardian.sol";
import { IAccount } from "../../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../../interfaces/IArcadiaFactory.sol";
import { IRouterTrampoline } from "../interfaces/IRouterTrampoline.sol";
import { IStrategyHook } from "../interfaces/IStrategyHook.sol";
import { PositionState } from "../state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../libraries/RebalanceLogic.sol";
import { RebalanceOptimizationMath } from "../libraries/RebalanceOptimizationMath.sol";
import { SafeApprove } from "../../libraries/SafeApprove.sol";
import { TickMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Abstract Rebalancer for Concentrated Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permissioned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
abstract contract Rebalancer is IActionBase, AbstractBase, Guardian {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The contract address of the Router Trampoline.
    IRouterTrampoline public immutable ROUTER_TRAMPOLINE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to rebalance the fees for, used as transient storage.
    address internal account;

    // A mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // A mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account.
    mapping(address accountOwner => mapping(address account => address initiator)) public accountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 maxClaimFee;
        // The maximum fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
        uint64 maxSwapFee;
        // The maximum relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 upperSqrtPriceDeviation;
        // The minimum relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 lowerSqrtPriceDeviation;
        // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
        uint64 minLiquidityRatio;
        // The contract address of the strategy hook.
        address strategyHook;
    }

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
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 claimFee;
        // The fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
        uint64 swapFee;
        // Calldata provided by the initiator to execute the swap.
        bytes swapData;
        // Strategy specific Calldata provided by the initiator.
        bytes strategyData;
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
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param routerTrampoline The contract address of the Router Trampoline.
     */
    constructor(address owner_, address arcadiaFactory, address routerTrampoline) Guardian(owner_) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        ROUTER_TRAMPOLINE = IRouterTrampoline(routerTrampoline);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setAssetManager()".
     * @param accountOwner The current owner of the Arcadia Account.
     * param status Bool indicating if the Asset Manager is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     */
    function onSetAssetManager(address accountOwner, bool, bytes calldata data) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (
            address initiator,
            uint256 maxClaimFee,
            uint256 maxSwapFee,
            uint256 maxTolerance,
            uint256 minLiquidityRatio,
            address strategyHook,
            bytes memory strategyData,
            bytes memory metaData_
        ) = abi.decode(data, (address, uint256, uint256, uint256, uint256, address, bytes, bytes));
        _setAccountInfo(
            msg.sender,
            accountOwner,
            initiator,
            maxClaimFee,
            maxSwapFee,
            maxTolerance,
            minLiquidityRatio,
            strategyHook,
            strategyData,
            metaData_
        );
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param maxClaimFee The maximum fee charged on claimed fees/rewards by the initiator, with 18 decimals precision.
     * @param maxSwapFee The maximum fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param strategyHook The contract address of the strategy hook.
     * @param strategyData Strategy specific data stored in the hook.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account_,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 maxTolerance,
        uint256 minLiquidityRatio,
        address strategyHook,
        bytes calldata strategyData,
        bytes calldata metaData_
    ) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address accountOwner = IAccount(account_).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();

        _setAccountInfo(
            account_,
            accountOwner,
            initiator,
            maxClaimFee,
            maxSwapFee,
            maxTolerance,
            minLiquidityRatio,
            strategyHook,
            strategyData,
            metaData_
        );
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param maxClaimFee The maximum fee charged on claimed fees/rewards by the initiator, with 18 decimals precision.
     * @param maxSwapFee The maximum fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param strategyHook The contract address of the strategy hook.
     * @param strategyData Strategy specific data stored in the hook.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function _setAccountInfo(
        address account_,
        address accountOwner,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 maxTolerance,
        uint256 minLiquidityRatio,
        address strategyHook,
        bytes memory strategyData,
        bytes memory metaData_
    ) internal {
        if (maxClaimFee > 1e18 || maxSwapFee > 1e18 || maxTolerance > 1e18 || minLiquidityRatio > 1e18) {
            revert InvalidValue();
        }

        accountToInitiator[accountOwner][account_] = initiator;
        accountInfo[account_] = AccountInfo({
            maxClaimFee: uint64(maxClaimFee),
            maxSwapFee: uint64(maxSwapFee),
            upperSqrtPriceDeviation: uint64(FixedPointMathLib.sqrt((1e18 + maxTolerance) * 1e18)),
            lowerSqrtPriceDeviation: uint64(FixedPointMathLib.sqrt((1e18 - maxTolerance) * 1e18)),
            minLiquidityRatio: uint64(minLiquidityRatio),
            strategyHook: strategyHook
        });
        metaData[account_] = metaData_;

        IStrategyHook(strategyHook).setStrategy(account_, strategyData);

        emit AccountInfoSet(account_, initiator, strategyHook);
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Rebalances a Concentrated Liquidity Positions, owned by an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function rebalance(address account_, InitiatorParams calldata initiatorParams) external whenNotPaused {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the initiator is set, account_ is an actual Arcadia Account.
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // If leftovers have to be withdrawn from account, get token0 and token1.
        address token0;
        address token1;
        if (initiatorParams.amount0 > 0 || initiatorParams.amount1 > 0) {
            (token0, token1) = _getUnderlyingTokens(initiatorParams.positionManager, initiatorParams.oldId);
        }

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(
            initiatorParams.positionManager,
            initiatorParams.oldId,
            token0,
            token1,
            initiatorParams.amount0,
            initiatorParams.amount1,
            abi.encode(msg.sender, initiatorParams)
        );

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param actionTargetData A bytes object containing the initiator and initiatorParams.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in rebalance().
        if (msg.sender != account) revert OnlyAccount();

        // Cache accountInfo.
        AccountInfo memory accountInfo_ = accountInfo[msg.sender];

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));
        address positionManager = initiatorParams.positionManager;

        // Validate initiatorParams.
        if (initiatorParams.claimFee > accountInfo_.maxClaimFee || initiatorParams.swapFee > accountInfo_.maxSwapFee) {
            revert InvalidValue();
        }

        // Get all pool and position related state.
        PositionState memory position = _getPositionState(positionManager, initiatorParams.oldId);

        // Rebalancer has withdrawn the underlying tokens from the Account.
        uint256[] memory balances = new uint256[](position.tokens.length);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        uint256[] memory fees = new uint256[](balances.length);

        // Call the strategy hook before the rebalance (view function, cannot modify state of pool or old position).
        // The strategy hook will return the new ticks of the position
        // (we override ticks of the memory pointer of the old position as these are no longer needed after this call).
        // Hook can be used to enforce additional strategy specific constraints, specific to the Account/Id.
        // Such as:
        // - Minimum Cool Down Periods.
        // - Excluding rebalancing of certain positions.
        // - ...
        (position.tickLower, position.tickUpper) = IStrategyHook(accountInfo_.strategyHook).beforeRebalance(
            msg.sender, positionManager, position, initiatorParams.strategyData
        );

        // Cache variables that are gas expensive to calculate and used multiple times.
        Cache memory cache = _getCache(accountInfo_, position, initiatorParams.trustedSqrtPrice);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (!isPoolBalanced(position.sqrtPrice, cache)) revert UnbalancedPool();

        // Claim pending yields and update balances.
        _claim(balances, fees, positionManager, position, initiatorParams.claimFee);

        // If the position is staked, unstake it.
        _unstake(balances, positionManager, position);

        // Remove liquidity of the position and update balances.
        _burn(balances, positionManager, position);

        // Get the rebalance parameters, based on a hypothetical swap through the pool itself without slippage.
        RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
            accountInfo_.minLiquidityRatio,
            position.fee,
            initiatorParams.swapFee,
            position.sqrtPrice,
            cache.sqrtRatioLower,
            cache.sqrtRatioUpper,
            balances[0] - fees[0],
            balances[1] - fees[1]
        );
        if (rebalanceParams.zeroToOne) fees[0] += rebalanceParams.amountInitiatorFee;
        else fees[1] += rebalanceParams.amountInitiatorFee;

        // Do the swap to rebalance the position.
        // This can be done either directly through the pool, or via a router with custom swap data.
        // For swaps directly through the pool, if slippage is bigger than calculated, the transaction will not immediately revert,
        // but excess slippage will be subtracted from the initiatorFee.
        // For swaps via a router, tokenOut should be the limiting factor when increasing liquidity.
        // Update balances after the swap.
        _swap(balances, fees, initiatorParams, position, rebalanceParams, cache);

        // Check that the pool is still balanced after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPrice might have moved and brought the pool out of balance.
        position.sqrtPrice = _getSqrtPrice(position);
        if (!isPoolBalanced(position.sqrtPrice, cache)) revert UnbalancedPool();

        // As explained before _swap(), tokenOut should be the limiting factor when increasing liquidity
        // therefore we only subtract the initiator fee from the amountOut, not from the amountIn.
        // Update balances, id and liquidity after the mint.
        (uint256 amount0Desired, uint256 amount1Desired) =
            rebalanceParams.zeroToOne ? (balances[0], balances[1] - fees[1]) : (balances[0] - fees[0], balances[1]);
        _mint(balances, positionManager, position, amount0Desired, amount1Desired);

        // Check that the actual liquidity of the position is above the minimum threshold.
        // This prevents loss of principal of the liquidity position due to slippage,
        // or malicious initiators who remove liquidity during a custom swap.
        if (position.liquidity < rebalanceParams.minLiquidity) revert InsufficientLiquidity();

        // If the position is staked, stake it.
        _stake(balances, positionManager, position);

        // Call the strategy hook after the rebalance (non view function).
        // Can be used to check additional constraints and persist state changes on the hook.
        IStrategyHook(accountInfo_.strategyHook).afterRebalance(
            msg.sender, positionManager, initiatorParams.oldId, position, initiatorParams.strategyData
        );

        // Approve the liquidity position and leftovers to be deposited back into the Account.
        // And transfer the initiator fees to the initiator.
        uint256 count = _approveAndTransfer(initiator, balances, fees, positionManager, position);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Rebalance(msg.sender, positionManager, initiatorParams.oldId, position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if the pool of a Liquidity Position is balanced.
     * @param sqrtPrice The sqrtPrice of the pool.
     * @param cache A struct with cached variables.
     * @return isBalanced Bool indicating if the pool is balanced.
     */
    function isPoolBalanced(uint256 sqrtPrice, Cache memory cache) public pure returns (bool isBalanced) {
        // Check if current price of the Pool is within accepted tolerance of the calculated trusted price.
        isBalanced = sqrtPrice > cache.lowerBoundSqrtPrice && sqrtPrice < cache.upperBoundSqrtPrice;
    }

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the cached variables.
     * @param accountInfo_ A struct with the account specific parameters.
     * @param position A struct with position and pool related variables.
     * @param trustedSqrtPrice The sqrtPrice the pool should have, given by the initiator.
     * @return cache A struct with cached variables.
     */
    function _getCache(AccountInfo memory accountInfo_, PositionState memory position, uint256 trustedSqrtPrice)
        internal
        view
        virtual
        returns (Cache memory cache)
    {
        // We do not handle the edge cases where the bounds of the sqrtPrice exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        cache = Cache({
            lowerBoundSqrtPrice: trustedSqrtPrice.mulDivDown(accountInfo_.lowerSqrtPriceDeviation, 1e18),
            upperBoundSqrtPrice: trustedSqrtPrice.mulDivDown(accountInfo_.upperSqrtPriceDeviation, 1e18),
            sqrtRatioLower: TickMath.getSqrtPriceAtTick(position.tickLower),
            sqrtRatioUpper: TickMath.getSqrtPriceAtTick(position.tickUpper)
        });
    }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     * @param rebalanceParams A struct with the rebalance parameters.
     * @param cache A struct with cached variables.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _swap(
        uint256[] memory balances,
        uint256[] memory fees,
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
                balances[0] - fees[0],
                balances[1] - fees[1],
                rebalanceParams.amountIn,
                rebalanceParams.amountOut
            );
            // Don't do swaps with zero amount.
            if (amountOut == 0) return;
            _swapViaPool(balances, position, rebalanceParams.zeroToOne, amountOut);
        } else {
            _swapViaRouter(balances, position, rebalanceParams.zeroToOne, initiatorParams.swapData);
        }
    }

    /**
     * @notice Swaps one token for another, via a router with custom swap data.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @dev Initiator has to route swap in such a way that at least minLiquidity of liquidity is added to the position after the swap.
     * And leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
     * and the initiator fee will be 0 (but the transaction will not revert).
     */
    function _swapViaRouter(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal virtual {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

        (address tokenIn, address tokenOut) =
            zeroToOne ? (position.tokens[0], position.tokens[1]) : (position.tokens[1], position.tokens[0]);

        // Send tokens to the Router Trampoline.
        ERC20(tokenIn).safeTransfer(address(ROUTER_TRAMPOLINE), amountIn);

        // Execute swap.
        (uint256 balanceIn, uint256 balanceOut) = ROUTER_TRAMPOLINE.execute(router, data, tokenIn, tokenOut, amountIn);

        // Update the balances.
        (balances[0], balances[1]) = zeroToOne
            ? (balances[0] - amountIn + balanceIn, balances[1] + balanceOut)
            : (balances[0] + balanceOut, balances[1] - amountIn + balanceIn);
    }

    /* ///////////////////////////////////////////////////////////////
                    APPROVE AND TRANSFER LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Approves the liquidity position and leftovers to be deposited back into the Account
     * and transfers the initiator fees to the initiator.
     * @param initiator The address of the initiator.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @return count The number of assets approved.
     */
    function _approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position
    ) internal returns (uint256 count) {
        // Approve the Liquidity Position.
        ERC721(positionManager).approve(msg.sender, position.id);

        // Transfer Initiator fees and approve the leftovers.
        address token;
        count = 1;
        for (uint256 i; i < balances.length; i++) {
            token = position.tokens[i];
            // If there are leftovers, deposit them back into the Account.
            if (balances[i] > fees[i]) {
                balances[i] = balances[i] - fees[i];
                ERC20(token).safeApproveWithRetry(msg.sender, balances[i]);
                count++;
            } else {
                fees[i] = balances[i];
                balances[i] = 0;
            }

            // Transfer Initiator fees to the initiator.
            if (fees[i] > 0) ERC20(token).safeTransfer(initiator, fees[i]);
            emit FeePaid(msg.sender, initiator, token, fees[i]);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             SKIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Recovers any native or ERC20 tokens left on the contract.
     * @param token The contract address of the token, or address(0) for native tokens.
     */
    function skim(address token) external onlyOwner whenNotPaused {
        if (account != address(0)) revert Reentered();

        if (token == address(0)) {
            (bool success, bytes memory result) = payable(msg.sender).call{ value: address(this).balance }("");
            require(success, string(result));
        } else {
            ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
}
