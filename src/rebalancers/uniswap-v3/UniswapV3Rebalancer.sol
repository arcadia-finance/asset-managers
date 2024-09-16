/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { CollectParams, DecreaseLiquidityParams, MintParams } from "./interfaces/INonfungiblePositionManager.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "../libraries/LiquidityAmounts.sol";
import { SqrtPriceMath } from "../libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
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
contract UniswapV3Rebalancer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum lower deviation of the pools actual sqrtPriceX96,
    // The maximum deviation of the actual pool price, in % with 18 decimals precision.
    uint256 public immutable MAX_TOLERANCE;

    // The maximum fee an initiator can set, with 6 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The ratio that limits the amount of slippage of the swap, with 18 decimals precision.
    // It is defined as the quotient between the minimal amount of liquidity that must be added,
    // and the amount of liquidity that would be added if the swap was executed through the pool without slippage.
    // MAX_SLIPPAGE_RATIO = minLiquidity / liquidityWithoutSlippage
    uint256 public immutable MAX_SLIPPAGE_RATIO;

    uint256 internal constant MAX_ITERATIONS = 50;

    // The minimal relative difference between liquidity0 and liquidity1, with 18 decimals precision.
    uint256 internal constant CONVERGENCE_THRESHOLD = 1e6;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Flag Indicating if a function is locked to protect against reentrancy.
    uint8 internal locked;

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
        uint24 fee;
        int24 newUpperTick;
        int24 newLowerTick;
        uint128 liquidity;
        uint128 usableLiquidity;
        uint256 sqrtPriceX96;
        uint256 lowerBoundSqrtPriceX96;
        uint256 upperBoundSqrtPriceX96;
    }

    // A struct used to store information for each specific initiator
    struct InitiatorInfo {
        uint256 upperSqrtPriceDeviation;
        uint256 lowerSqrtPriceDeviation;
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
    error NotConverged();
    error OnlyAccount();
    error OnlyPool();
    error Reentered();
    error UnbalancedPool();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Rebalance(address indexed account, uint256 id);

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
     * @param id The id of the Liquidity Position to rebalance.
     * @param lowerTick The new lower tick to rebalance to.
     * @param upperTick The new upper tick to rebalance to.
     * @dev When both lowerTick and upperTick are zero, ticks will be updated with same tick-spacing as current position
     * and with a balanced, 50/50 ratio around current tick.
     */
    function rebalancePosition(address account_, uint256 id, int24 lowerTick, int24 upperTick, bytes calldata swapData)
        external
    {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (ownerToAccountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InitiatorNotValid();

        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeActionDataRebalancer(
            address(UniswapV3Logic.POSITION_MANAGER), id, msg.sender, lowerTick, upperTick, swapData
        );

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit Rebalance(account_, id);
        //require(false, "test");
    }

    event Log(string name, uint256 value);

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param rebalanceData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return assetData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata rebalanceData) external override returns (ActionData memory assetData) {
        // Caller should be the Account, provided as input in rebalancePosition().
        if (msg.sender != account) revert OnlyAccount();

        // Decode rebalanceData.
        bytes memory swapData;
        uint256 id;
        PositionState memory position;
        address initiator;
        {
            int24 lowerTick;
            int24 upperTick;
            (assetData, initiator, lowerTick, upperTick, swapData) =
                abi.decode(rebalanceData, (ActionData, address, int24, int24, bytes));
            id = assetData.assetIds[0];

            // Fetch and cache all position related data.
            position = getPositionState(id, lowerTick, upperTick, initiator);
        }

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (isPoolUnbalanced(position)) revert UnbalancedPool();

        // Remove liquidity of the position and claim outstanding fees to get full amounts of token0 and token1
        // for rebalance.
        UniswapV3Logic.POSITION_MANAGER.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: id,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        (uint256 balance0, uint256 balance1) = UniswapV3Logic.POSITION_MANAGER.collect(
            CollectParams({
                tokenId: id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Burn the position
        UniswapV3Logic.POSITION_MANAGER.burn(id);

        bool zeroToOne;
        uint256 amountInitiatorFee;
        uint256 minLiquidity;
        {
            // Rebalance the position so that the maximum liquidity can be added for new ticks.
            // The Pool must still be balanced after the swap.
            uint256 amountInWithFees;
            uint256 amountOut;
            {
                // Cache initiator fee
                uint256 initiatorFee = initiatorInfo[initiator].fee;
                (zeroToOne, amountInWithFees, amountOut) = getSwapParameters(position, balance0, balance1, initiatorFee);

                // Get initiator fee amount.
                amountInitiatorFee = amountInWithFees.mulDivDown(initiatorFee, 1e18);
            }

            // Calculate the minimum amount of liquidity that should be added to the position.
            {
                uint256 liquidityWithoutSlippage = LiquidityAmounts.getLiquidityForAmounts(
                    uint160(position.sqrtPriceX96),
                    TickMath.getSqrtRatioAtTick(position.newUpperTick),
                    TickMath.getSqrtRatioAtTick(position.newLowerTick),
                    zeroToOne ? balance0 - amountInWithFees : balance0 + amountOut,
                    zeroToOne ? balance1 + amountOut : balance1 - amountInWithFees
                );
                minLiquidity = liquidityWithoutSlippage.mulDivDown(MAX_SLIPPAGE_RATIO, 1e18);
            }

            if (swapData.length == 0) {
                // Swap via the pool of the position directly.
                amountOut = getAmountOutWithSlippage(
                    position.fee,
                    position.usableLiquidity,
                    uint160(position.sqrtPriceX96),
                    TickMath.getSqrtRatioAtTick(position.newLowerTick),
                    TickMath.getSqrtRatioAtTick(position.newUpperTick),
                    zeroToOne ? balance0 - amountInitiatorFee : balance0,
                    zeroToOne ? balance1 : balance1 - amountInitiatorFee,
                    amountInWithFees - amountInitiatorFee,
                    zeroToOne
                );
                if (_swap(position, zeroToOne, amountOut)) revert UnbalancedPool();
                balance0 = zeroToOne ? ERC20(position.token0).balanceOf(address(this)) : balance0 + amountOut;
                balance1 = zeroToOne ? balance1 + amountOut : ERC20(position.token1).balanceOf(address(this));
                // balance0 = ERC20(position.token0).balanceOf(address(this));
                // balance1 = ERC20(position.token1).balanceOf(address(this));
            } else {
                // Swap via custom provided routing data.
                _swap(position, zeroToOne, amountInWithFees - amountInitiatorFee, swapData);
                balance0 = ERC20(position.token0).balanceOf(address(this));
                balance1 = ERC20(position.token1).balanceOf(address(this));
            }
        }

        // The approval for at least one token after increasing liquidity will remain non-zero.
        // We have to set approval first to 0 for ERC20 tokens that require the approval to be set to zero
        // before setting it to a non-zero value.
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token0).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), balance0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), 0);
        ERC20(position.token1).safeApprove(address(UniswapV3Logic.POSITION_MANAGER), balance1);

        uint256 newTokenId;
        {
            uint256 liquidity;
            uint256 amount0;
            uint256 amount1;
            (newTokenId, liquidity, amount0, amount1) = UniswapV3Logic.POSITION_MANAGER.mint(
                MintParams({
                    token0: position.token0,
                    token1: position.token1,
                    fee: position.fee,
                    tickLower: position.newLowerTick,
                    tickUpper: position.newUpperTick,
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
            if (liquidity < minLiquidity) revert InsufficientLiquidity();

            // Update balances.
            balance0 -= amount0;
            balance1 -= amount1;
        }

        // Transfer fee to the initiator.
        if (zeroToOne) {
            if (balance0 > amountInitiatorFee) {
                balance0 -= amountInitiatorFee;
                ERC20(position.token0).safeTransfer(initiator, amountInitiatorFee);
            } else {
                ERC20(position.token0).safeTransfer(initiator, balance0);
                balance0 = 0;
            }
        } else {
            if (balance1 > amountInitiatorFee) {
                balance1 -= amountInitiatorFee;
                ERC20(position.token1).safeTransfer(initiator, amountInitiatorFee);
            } else {
                ERC20(position.token1).safeTransfer(initiator, balance1);
                balance1 = 0;
            }
        }

        ActionData memory returnedAssets;
        {
            uint256 assetsCount = 1 + (balance0 > 0 ? 1 : 0) + (balance1 > 0 ? 1 : 0);

            returnedAssets.assets = new address[](assetsCount);
            returnedAssets.assetIds = new uint256[](assetsCount);
            returnedAssets.assetAmounts = new uint256[](assetsCount);
            returnedAssets.assetTypes = new uint256[](assetsCount);

            // Add newly minted Liquidity Position first.
            returnedAssets.assets[0] = address(UniswapV3Logic.POSITION_MANAGER);
            returnedAssets.assetIds[0] = newTokenId;
            returnedAssets.assetAmounts[0] = 1;
            returnedAssets.assetTypes[0] = 2;

            // Track the next index for token0 and token1.
            uint256 index = 1;

            // In case of leftovers after the mint, these should be deposited back into the Account.
            if (balance0 > 0) {
                ERC20(position.token0).approve(msg.sender, balance0);
                returnedAssets.assets[index] = position.token0;
                returnedAssets.assetAmounts[index] = balance0;
                returnedAssets.assetTypes[index] = 1;
                ++index;
            }

            if (balance1 > 0) {
                ERC20(position.token1).approve(msg.sender, balance1);
                returnedAssets.assets[index] = position.token1;
                returnedAssets.assetAmounts[index] = balance1;
                returnedAssets.assetTypes[index] = 1;
            }
        }

        // Approve ActionHandler to deposit Liquidity Position back into the Account.
        UniswapV3Logic.POSITION_MANAGER.approve(msg.sender, newTokenId);

        return returnedAssets;
    }

    /* ///////////////////////////////////////////////////////////////
                        INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */
    /**
     * @notice Sets an initiator for an Account. An initiator will be permisionned to rebalance any UniswapV3
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
        uint256 upperSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);
        if (initiatorInfo_.initialized == true && upperSqrtPriceDeviation > initiatorInfo_.upperSqrtPriceDeviation) {
            revert DecreaseToleranceOnly();
        }

        initiatorInfo_.lowerSqrtPriceDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        initiatorInfo_.upperSqrtPriceDeviation = upperSqrtPriceDeviation;

        // Set initiator as initialized if it wasn't already.
        if (initiatorInfo_.initialized == false) initiatorInfo_.initialized = true;

        initiatorInfo[msg.sender] = initiatorInfo_;
    }

    /* ///////////////////////////////////////////////////////////////
                        SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the swap parameters to optimize the total value that can be added as liquidity.
     * @param position Struct with the position data.
     * @param amount0 The amount of token0 that is available for the rebalance.
     * @param amount1 The amount of token1 that is available for the rebalance.
     * @param initiatorFee The fee of the initiator.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountIn The amount of tokenIn.
     * @dev Slippage must be limited, the contract enforces that the pool is still balanced after the swap.
     */
    function getSwapParameters(PositionState memory position, uint256 amount0, uint256 amount1, uint256 initiatorFee)
        public
        pure
        returns (bool zeroToOne, uint256 amountIn, uint256 amountOut)
    {
        uint256 sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);
        uint256 sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);

        // Total fee is pool fee + initiator fee, with 18 decimals precision.
        // Since Uniswap uses 6 decimals precision for the fee, we have to multiply the pool fee by 1e12.
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;

        if (position.sqrtPriceX96 >= sqrtRatioUpper) {
            // Position is out of range and fully in token 1.
            // Swap full amount of token0 to token1.
            zeroToOne = true;
            amountIn = amount0;
            amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0, fee);
        } else if (position.sqrtPriceX96 <= sqrtRatioLower) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            amountIn = amount1;
            amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amount1, fee);
        } else {
            // Get target ratio in token1 terms.
            uint256 targetRatio = UniswapV3Logic._getTargetRatio(position.sqrtPriceX96, sqrtRatioLower, sqrtRatioUpper);

            // Calculate the total position value in token1 equivalent:
            uint256 token0ValueInToken1 = UniswapV3Logic._getSpotValue(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            if (currentRatio < targetRatio) {
                // Swap token0 partially to token1.
                zeroToOne = true;
                uint256 denominator = 1e18 + targetRatio.mulDivDown(fee, 1e18 - fee);
                amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, denominator);
                amountIn = UniswapV3Logic._getAmountIn(position.sqrtPriceX96, true, amountOut, fee);
            } else {
                // Swap token1 partially to token0.
                zeroToOne = false;
                uint256 denominator = 1e18 - targetRatio.mulDivDown(fee, 1e18);
                amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, denominator);
                amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amountIn, fee);
            }
        }
    }

    event Log(uint256 i, uint256 amountIn, uint256 amountOut, uint160 sqrtPriceNew);

    function getAmountOutWithSlippage(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        bool zeroToOne
    ) public returns (uint256 amountOut) {
        uint256 amountInLessFee;
        uint160 sqrtPriceNew = sqrtPriceOld;
        // We iteratively solve for sqrtPrice, amountOut and amountIn, so that the maximal amount of liquidity can be added to the position.
        if (zeroToOne) {
            for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
                emit Log(i, amountIn, amountOut, sqrtPriceNew);
                // Calculate, for a given amountIn, the new sqrtPrice and amountOut taking into account slippage.
                amountInLessFee = amountIn.mulDivUp(1e6 - fee, 1e6);
                sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    sqrtPriceOld, usableLiquidity, amountInLessFee, true
                );
                amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false);

                if (sqrtPriceNew > sqrtRatioUpper) {
                    // Position is out of range and fully in token0.
                    // If amountIn is equal to amount0, exact solution is found.
                    // If not we have to set amountIn equal to amount0 and do one more iteration.
                    if (amountIn == amount0) return amountOut;
                    else amountIn = amount0;
                } else {
                    {
                        bool converged;
                        (converged, amountIn, amountOut) = _isConverged(
                            sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPriceNew, true
                        );
                        // Check if stop criterium of iteration is met:
                        // The relative difference between liquidity0 and liquidity1 is below the convergence threshold.
                        if (converged) return amountOut;
                    }
                    // If not, we do an extra iteration.
                }
            }
        } else {
            for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
                // Calculate, for a given amountIn, the new sqrtPrice and amountOut taking into account slippage.
                amountInLessFee = amountIn.mulDivUp(1e6 - fee, 1e6);
                sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceOld, usableLiquidity, amountInLessFee, true
                );
                amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
                emit Log(i, amountIn, amountOut, sqrtPriceNew);

                if (sqrtPriceNew < sqrtRatioLower) {
                    // Position is out of range and fully in token1.
                    // If amountIn is equal to amount1, exact solution is found.
                    // If not we have to set amountIn equal to amount1 and do one more iteration.
                    if (amountIn == amount1) return amountOut;
                    else amountIn = amount1;
                } else {
                    {
                        bool converged;
                        (converged, amountIn, amountOut) = _isConverged(
                            sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPriceNew, false
                        );
                        // Check if stop criterium of iteration is met:
                        // The relative difference between liquidity0 and liquidity1 is below the convergence threshold.
                        if (converged) return amountOut;
                    }
                    // If not, we do an extra iteration.
                }
            }
        }
        // Revert if the solution did not converge within MAX_ITERATIONS steps.
        revert NotConverged();
    }

    function _getAmountInMaximizingLiquidity(
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountOut,
        bool zeroToOne
    ) internal returns (uint256 amountIn) {
        amountIn = zeroToOne
            ? amount0
                - FullMath.mulDiv(amount1 + amountOut, UniswapV3Logic.Q192, sqrtRatioUpper * sqrtPrice).mulDivDown(
                    sqrtRatioUpper - sqrtPrice, sqrtPrice - sqrtRatioLower
                )
            : amount1
                - FullMath.mulDiv(amount0 + amountOut, sqrtRatioUpper * sqrtPrice, UniswapV3Logic.Q192).mulDivDown(
                    sqrtPrice - sqrtRatioLower, sqrtRatioUpper - sqrtPrice
                );
    }

    event Log2(uint256 liquidity0, uint256 liquidity1, uint256 relDiff);

    function _isConverged(
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPrice,
        bool zeroToOne
    ) internal returns (bool converged, uint256 amountIn_, uint256 amountOut_) {
        uint128 avgLiquidity;
        {
            uint128 liquidity0;
            uint128 liquidity1;
            if (zeroToOne) {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPrice, sqrtRatioUpper, amount0 - amountIn);
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, sqrtPrice, amount1 + amountOut);
            } else {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPrice, sqrtRatioUpper, amount0 + amountOut);
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, sqrtPrice, amount1 - amountIn);
            }
            avgLiquidity = (liquidity0 + liquidity1) / 2;

            // Calculate the relative difference of liquidity0 and liquidity1.
            uint256 relDiff = 1e18
                - (
                    liquidity0 < liquidity1
                        ? uint256(liquidity0).mulDivDown(1e18, liquidity1)
                        : uint256(liquidity1).mulDivDown(1e18, liquidity0)
                );
            emit Log2(liquidity0, liquidity1, relDiff);
            converged = relDiff < CONVERGENCE_THRESHOLD;
        }

        if (zeroToOne) {
            amountIn_ = amount0 - LiquidityAmounts.getAmount0ForLiquidity(sqrtPrice, sqrtRatioUpper, avgLiquidity);
            amountOut_ = LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioLower, sqrtPrice, avgLiquidity) - amount1;
        } else {
            amountOut_ = LiquidityAmounts.getAmount0ForLiquidity(sqrtPrice, sqrtRatioUpper, avgLiquidity) - amount0;
            amountIn_ = amount1 - LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioLower, sqrtPrice, avgLiquidity);
        }
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V3 Pool of the Liquidity Position.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced due to slippage of the swap.
     */
    function _swap(PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        returns (bool isPoolUnbalanced_)
    {
        // Don't do swaps with zero amount.
        if (amountOut == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Do the swap.
        bytes memory data = abi.encode(position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IUniswapV3Pool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        isPoolUnbalanced_ = (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0)));
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
        if (UniswapV3Logic._computePoolAddress(token0, token1, fee) != msg.sender) revert OnlyPool();

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice Allows an initiator to perform an arbitrary swap.
     * @param amountIn The amount of tokenIn that must be swapped.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData A bytes object containing a contract address and another bytes object with the calldata to send to that address.
     * @dev In order for such a swap to be valid, the amountOut should be at least equal to the amountOut expected if the swap
     * occured in the pool of the position itself. The amountIn should also fully have been utilized, to keep target ratio valid.
     */
    function _swap(PositionState memory position, bool zeroToOne, uint256 amountIn, bytes memory swapData) internal {
        (address to, bytes memory data) = abi.decode(swapData, (address, bytes));

        // Approve token to swap.
        address tokenToSwap = zeroToOne ? position.token0 : position.token1;
        ERC20(tokenToSwap).approve(to, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = to.call(data);
        require(success, string(result));

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
        // Uniswap V3 pool should still be balanced.
        if (sqrtPriceX96 < position.lowerBoundSqrtPriceX96 || sqrtPriceX96 > position.upperBoundSqrtPriceX96) {
            revert UnbalancedPool();
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    POSITION AND POOL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @param lowerTick The lower tick of the newly minted position.
     * @param upperTick The upper tick of the newly minted position.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id, int24 lowerTick, int24 upperTick, address initiator)
        public
        view
        returns (PositionState memory position)
    {
        // Get data of the Liquidity Position.
        int24 currentLowerTick;
        int24 currentUpperTick;
        (,, position.token0, position.token1, position.fee, currentLowerTick, currentUpperTick, position.liquidity,,,,)
        = UniswapV3Logic.POSITION_MANAGER.positions(id);

        // Get trusted USD prices for 1e18 gwei of token0 and token1.
        (uint256 usdPriceToken0, uint256 usdPriceToken1) =
            ArcadiaLogic._getValuesInUsd(position.token0, position.token1);

        // Get data of the Liquidity Pool.
        position.pool = UniswapV3Logic._computePoolAddress(position.token0, position.token1, position.fee);
        int24 currentTick;
        (position.sqrtPriceX96, currentTick,,,,,) = IUniswapV3Pool(position.pool).slot0();
        position.usableLiquidity = IUniswapV3Pool(position.pool).liquidity() - position.liquidity;

        // Store the new ticks for the rebalance
        if (lowerTick == 0 && upperTick == 0) {
            int24 tickSpacing = IUniswapV3Pool(position.pool).tickSpacing();
            int24 halfRangeTicks = ((currentUpperTick - currentLowerTick) / tickSpacing) / 2;
            halfRangeTicks *= tickSpacing;
            position.newUpperTick = currentTick + halfRangeTicks;
            position.newLowerTick = currentTick - halfRangeTicks;
        } else {
            position.newUpperTick = upperTick;
            position.newLowerTick = lowerTick;
        }

        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        uint256 lowerBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        uint256 upperBoundSqrtPriceX96 =
            trustedSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
        uint256 minSqrtRatio = TickMath.MIN_SQRT_RATIO;
        uint256 maxSqrtRatio = TickMath.MAX_SQRT_RATIO;
        position.lowerBoundSqrtPriceX96 =
            lowerBoundSqrtPriceX96 <= minSqrtRatio ? minSqrtRatio + 1 : lowerBoundSqrtPriceX96;
        position.upperBoundSqrtPriceX96 =
            upperBoundSqrtPriceX96 >= maxSqrtRatio ? maxSqrtRatio - 1 : upperBoundSqrtPriceX96;
    }

    /**
     * @notice returns if the pool of a Liquidity Position is unbalanced.
     * @param position Struct with the position data.
     * @return isPoolUnbalanced_ Bool indicating if the pool is unbalanced.
     */
    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        // Check if current priceX96 of the Pool is within accepted tolerance of the calculated trusted priceX96.
        isPoolUnbalanced_ = position.sqrtPriceX96 < position.lowerBoundSqrtPriceX96
            || position.sqrtPriceX96 > position.upperBoundSqrtPriceX96;
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
