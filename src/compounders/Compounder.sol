/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AbstractBase } from "../base/AbstractBase.sol";
import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { PositionState } from "../state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../libraries/RebalanceLogic.sol";
import { RebalanceOptimizationMath } from "../libraries/RebalanceOptimizationMath.sol";
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
abstract contract Compounder is IActionBase, AbstractBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_FEE;

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

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 claimFee;
        // The fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
        uint64 swapFee;
        // The maximum relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 upperSqrtPriceDeviation;
        // The miminumù relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 lowerSqrtPriceDeviation;
        // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
        uint64 minLiquidityRatio;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 id;
        // The amount of token0 withdrawn from the account.
        uint128 amount0;
        // The amount of token1 withdrawn from the account.
        uint128 amount1;
        // The sqrtPrice the pool should have, given by the initiator.
        uint256 trustedSqrtPrice;
        // Calldata provided by the initiator to execute the swap.
        bytes swapData;
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

    // A struct with information for each specific initiator.
    struct InitiatorInfo {
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 claimFee;
        // The fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
        uint64 swapFee;
        // The maximum relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 upperSqrtPriceDeviation;
        // The miminumù relative deviation the pool can have from the trustedSqrtPrice, with 18 decimals precision.
        uint64 lowerSqrtPriceDeviation;
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

    event AccountInfoSet(address indexed account, address indexed initiator);
    event Compound(address indexed account, address indexed positionManager, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxFee The maximum fee an initiator can set, with 18 decimals precision.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     */
    constructor(address arcadiaFactory, uint256 maxFee, uint256 maxTolerance, uint256 minLiquidityRatio) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        MAX_FEE = maxFee;
        MAX_TOLERANCE = maxTolerance;
        MIN_LIQUIDITY_RATIO = minLiquidityRatio;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     */
    function setAccountInfo(address account_, address initiator) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        accountToInitiator[owner][account_] = initiator;

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the information requested for an initiator.
     * @param claimFee The fee charged on claimed fees/rewards by the initiator, with 18 decimals precision.
     * @param swapFee The fee charged on the ideal (without slippage) amountIn by the initiator, with 18 decimals precision.
     * @param tolerance The maximum deviation of the actual pool price,
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPrice for the lower and upper boundaries.
     */
    function setInitiatorInfo(uint256 claimFee, uint256 swapFee, uint256 tolerance, uint256 minLiquidityRatio)
        external
    {
        if (account != address(0)) revert Reentered();

        // Cache struct
        InitiatorInfo memory initiatorInfo_ = initiatorInfo[msg.sender];

        // Calculation required for checks.
        uint64 upperSqrtPriceDeviation = uint64(FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));

        // Check if initiator is already set.
        if (initiatorInfo_.minLiquidityRatio > 0) {
            // If so, the initiator can only change parameters to more favourable values for users.
            if (
                claimFee > initiatorInfo_.claimFee || swapFee > initiatorInfo_.swapFee
                    || upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation
                    || minLiquidityRatio < initiatorInfo_.minLiquidityRatio || minLiquidityRatio > 1e18
            ) revert InvalidValue();
        } else {
            // If not, the parameters can not exceed certain thresholds.
            if (
                claimFee > MAX_FEE || swapFee > MAX_FEE || tolerance > MAX_TOLERANCE
                    || minLiquidityRatio < MIN_LIQUIDITY_RATIO || minLiquidityRatio > 1e18
            ) {
                revert InvalidValue();
            }
        }

        initiatorInfo_.claimFee = uint64(claimFee);
        initiatorInfo_.swapFee = uint64(swapFee);
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
    function compound(address account_, InitiatorParams calldata initiatorParams) external {
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
            (token0, token1) = _getUnderlyingTokens(initiatorParams.positionManager, initiatorParams.id);
        }

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(
            initiatorParams.positionManager,
            initiatorParams.id,
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

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));
        address positionManager = initiatorParams.positionManager;

        // Get all pool and position related state.
        PositionState memory position = _getPositionState(positionManager, initiatorParams.id);

        // Rebalancer has withdrawn the underlying tokens from the Account.
        uint256[] memory balances = new uint256[](position.tokens.length);
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;
        uint256[] memory fees = new uint256[](balances.length);

        // Cache variables that are gas expensive to calcultate and used multiple times.
        Cache memory cache = _getCache(initiator, position, initiatorParams.trustedSqrtPrice);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (!isPoolBalanced(position.sqrtPrice, cache)) revert UnbalancedPool();

        // Claim pending fees/rewards and update balances.
        _claim(balances, fees, positionManager, position, initiatorInfo[initiator].claimFee);

        // If the position is staked, unstake it.
        _unstake(balances, positionManager, position);

        // Get the rebalance parameters, based on a hypothetical swap through the pool itself without slippage.
        RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
            initiatorInfo[initiator].minLiquidityRatio,
            position.fee,
            initiatorInfo[initiator].swapFee,
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
        // Increase liquidity, update balances and delta liquidity.
        {
            (uint256 amount0Desired, uint256 amount1Desired) =
                rebalanceParams.zeroToOne ? (balances[0], balances[1] - fees[1]) : (balances[0] - fees[0], balances[1]);
            // Increase liquidity, update balances and liquidity
            _increaseLiquidity(balances, positionManager, position, amount0Desired, amount1Desired);
        }

        // Check that the actual liquidity of the position is above the minimum threshold.
        // This prevents loss of principal of the liquidity position due to slippage,
        // or malicious initiators who remove liquidity during a custom swap.
        if (position.liquidity < rebalanceParams.minLiquidity) revert InsufficientLiquidity();

        // If the position is staked, stake it.
        _stake(balances, positionManager, position);

        // Approve the liquidity position and leftovers to be deposited back into the Account.
        // And transfer the initiator fees to the initiator.
        uint256 count = _approveAndTransfer(initiator, balances, fees, positionManager, position);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Compound(msg.sender, positionManager, position.id);
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
     * @param initiator The address of the initiator.
     * @param position A struct with position and pool related variables.
     * @param trustedSqrtPrice The sqrtPrice the pool should have, given by the initiator.
     * @return cache A struct with cached variables.
     */
    function _getCache(address initiator, PositionState memory position, uint256 trustedSqrtPrice)
        internal
        view
        virtual
        returns (Cache memory cache)
    {
        // We do not handle the edge cases where the bounds of the sqrtPrice exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        cache = Cache({
            lowerBoundSqrtPrice: trustedSqrtPrice.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18),
            upperBoundSqrtPrice: trustedSqrtPrice.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18),
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

        // Approve token to swap.
        ERC20(zeroToOne ? position.tokens[0] : position.tokens[1]).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Update the balances.
        balances[0] = ERC20(position.tokens[0]).balanceOf(address(this));
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
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
        count = 1;
        for (uint256 i; i < balances.length; i++) {
            // Skip assets with no balance.
            if (balances[i] == 0) continue;

            // If there are leftovers, deposit them back into the Account.
            if (balances[i] > fees[i]) {
                balances[i] = balances[i] - fees[i];
                ERC20(position.tokens[i]).safeApproveWithRetry(msg.sender, balances[i]);
                count++;
            } else {
                fees[i] = balances[i];
                balances[i] = 0;
            }

            // Transfer Initiator fees to the initiator.
            if (fees[i] > 0) ERC20(position.tokens[i]).safeTransfer(initiator, fees[i]);
        }
    }
}
