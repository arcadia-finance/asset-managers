/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Actions } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/Actions.sol";
import { BalanceDelta } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IHooks } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { IPermit2 } from "./interfaces/IPermit2.sol";
import { IPoolManager } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { IPositionManagerV4 } from "./interfaces/IPositionManagerV4.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { LiquidityAmounts } from "../libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { Rebalancer } from "./Rebalancer.sol";
import { RebalanceParams } from "./libraries/RebalanceLogic.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { StateLibrary } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Rebalancer for Uniswap V4 Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permisionned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPriceX96 input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 * @dev The rebalancer must not be used for Pools of native ETH - WETH.
 */
contract RebalancerUniswapV4 is Rebalancer {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    using StateLibrary for IPoolManager;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Uniswap v4 Position Manager.
    IPositionManagerV4 internal immutable POSITION_MANAGER;

    // The Permit2 contract.
    IPermit2 internal immutable PERMIT_2;

    // The Uniswap V4 PoolManager contract.
    IPoolManager internal immutable POOL_MANAGER;

    // The contract address of WETH.
    address internal immutable WETH;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping if permit2 has been approved for a certain token.
    mapping(address token => bool approved) internal approved;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error OnlyPoolManager();

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
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param permit2 The contract address of Permit2.
     * @param poolManager The contract address of the Uniswap v4 Pool Manager.
     * @param weth The contract address of WETH.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address permit2,
        address poolManager,
        address weth
    ) Rebalancer(arcadiaFactory, maxTolerance, maxInitiatorFee, minLiquidityRatio) {
        POSITION_MANAGER = IPositionManagerV4(positionManager);
        PERMIT_2 = IPermit2(permit2);
        POOL_MANAGER = IPoolManager(poolManager);
        WETH = weth;
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the rebalancer.
     * @param positionManager the contract address of the position manager to check.
     */
    function isPositionManager(address positionManager) public view override returns (bool) {
        return positionManager == address(POSITION_MANAGER);
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
        override
        returns (address token0, address token1)
    {
        (PoolKey memory poolKey,) = POSITION_MANAGER.getPoolAndPositionInfo(initiatorParams.oldId);
        token0 = Currency.unwrap(poolKey.currency0);
        token1 = Currency.unwrap(poolKey.currency1);

        // If token0 is in native ETH, we need to withdraw wrapped eth from the Account.
        if (token0 == address(0)) token0 = WETH;
    }

    /**
     * @notice Returns the position and pool related state.
     * @param initiatorParams A struct with the initiator parameters.
     * @return balances The balances of the underlying tokens of the position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(InitiatorParams memory initiatorParams)
        internal
        view
        override
        returns (uint256[] memory balances, PositionState memory position)
    {
        // Positions have two underlying tokens.
        position.tokens = new address[](2);
        balances = new uint256[](2);

        // Rebalancer has withdrawn the underlying tokens from the Account.
        balances[0] = initiatorParams.amount0;
        balances[1] = initiatorParams.amount1;

        // Get data of the Liquidity Position.
        position.id = initiatorParams.oldId;
        (PoolKey memory poolKey, PositionInfo info) = POSITION_MANAGER.getPoolAndPositionInfo(position.id);
        position.tickLower = info.tickLower();
        position.tickUpper = info.tickUpper();
        bytes32 positionId = keccak256(
            abi.encodePacked(address(POSITION_MANAGER), info.tickLower(), info.tickUpper(), bytes32(position.id))
        );
        position.liquidity = POOL_MANAGER.getPositionLiquidity(poolKey.toId(), positionId);

        // Get data of the Liquidity Pool.
        position.pool = address(poolKey.hooks);
        position.tokens[0] = Currency.unwrap(poolKey.currency0);
        position.tokens[1] = Currency.unwrap(poolKey.currency1);
        position.fee = poolKey.fee;
        position.tickSpacing = poolKey.tickSpacing;
        (position.sqrtPriceX96, position.tickCurrent,,) = POOL_MANAGER.getSlot0(poolKey.toId());
    }

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(Rebalancer.PositionState memory position)
        internal
        view
        override
        returns (uint128 liquidity)
    {
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(position.tokens[0]),
            Currency.wrap(position.tokens[1]),
            position.fee,
            position.tickSpacing,
            IHooks(position.pool)
        );
        liquidity = POOL_MANAGER.getLiquidity(poolKey.toId());
    }

    /**
     * @notice Returns the sqrtPriceX96 of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPriceX96 The sqrtPriceX96 of the Pool.
     */
    function _getSqrtPriceX96(Rebalancer.PositionState memory position)
        internal
        view
        override
        returns (uint160 sqrtPriceX96)
    {
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(position.tokens[0]),
            Currency.wrap(position.tokens[1]),
            position.fee,
            position.tickSpacing,
            IHooks(position.pool)
        );
        (sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(poolKey.toId());
    }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param initiatorParams A struct with the initiator parameters.
     * @param position A struct with position and pool related variables.
     */
    function _burn(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory
    ) internal override {
        // Generate calldata to burn the position and collect the underlying assets.
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.BURN_POSITION));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        Currency currency0 = Currency.wrap(position.tokens[0]);
        Currency currency1 = Currency.wrap(position.tokens[1]);
        params[0] = abi.encode(position.id, 0, 0, "");
        params[1] = abi.encode(currency0, currency1, address(this));

        bytes memory burnParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities(burnParams, block.timestamp);

        // If token0 is in native ETH, and weth was withdrawn from the account, unwrap it.
        if (position.tokens[0] == address(0) && initiatorParams.amount0 > 0) {
            IWETH(WETH).withdraw(initiatorParams.amount0);
        }

        // Update the balances, token0 might be native ETH.
        balances[0] = Currency.wrap(position.tokens[0]).balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param rebalanceParams A struct with the rebalance parameters.
     * @param cache A struct with cached variables.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    function _swapViaPool(
        uint256[] memory balances,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint256 amountOut
    ) internal override {
        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(rebalanceParams.zeroToOne ? cache.lowerBoundSqrtPriceX96 : cache.upperBoundSqrtPriceX96);

        // Do the swap.
        bytes memory swapData = abi.encode(
            IPoolManager.SwapParams({
                zeroForOne: rebalanceParams.zeroToOne,
                amountSpecified: int256(amountOut),
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            PoolKey(
                Currency.wrap(position.tokens[0]),
                Currency.wrap(position.tokens[1]),
                position.fee,
                position.tickSpacing,
                IHooks(position.pool)
            )
        );
        bytes memory results = POOL_MANAGER.unlock(swapData);

        // Check that pool is still balanced.
        // If sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received, the pool is not balanced anymore.
        // By setting the sqrtPriceX96 to sqrtPriceLimitX96, the transaction will revert on the balance check.
        BalanceDelta swapDelta = abi.decode(results, (BalanceDelta));
        int256 deltaAmount0 = swapDelta.amount0();
        int256 deltaAmount1 = swapDelta.amount1();
        if (amountOut > (rebalanceParams.zeroToOne ? uint256(deltaAmount1) : uint256(deltaAmount0))) {
            position.sqrtPriceX96 = sqrtPriceLimitX96;
        }

        // Update the balances.
        balances[0] =
            rebalanceParams.zeroToOne ? balances[0] - uint256(-deltaAmount0) : balances[0] + uint256(deltaAmount0);
        balances[1] =
            rebalanceParams.zeroToOne ? balances[1] + uint256(deltaAmount1) : balances[1] - uint256(-deltaAmount1);
    }

    /**
     * @notice Callback function executed during the unlock phase of a Uniswap V4 pool operation.
     * @param data The encoded swap parameters and pool key.
     * @return results The encoded BalanceDelta result from the swap operation.
     */
    function unlockCallback(bytes calldata data) external payable returns (bytes memory results) {
        if (msg.sender != address(POOL_MANAGER)) revert OnlyPoolManager();

        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));

        // Do the swap.
        BalanceDelta delta = POOL_MANAGER.swap(poolKey, params, "");
        results = abi.encode(delta);

        // Processes token balance changes.
        _processSwapDelta(delta, poolKey.currency0, poolKey.currency1);
    }

    /**
     * @notice Processes token balance changes resulting from a swap operation.
     * @param delta The BalanceDelta containing the positive/negative changes in token amounts.
     * @param currency0 The address of the first token in the pair.
     * @param currency1 The address of the second token in the pair.
     * @dev Handles token transfers between the contract and the Pool Manager based on delta values:
     *  - For tokens owed to the Pool Manager: transfers tokens and calls settle().
     *  - For tokens owed from the Pool Manager: calls take() to receive tokens.
     */
    function _processSwapDelta(BalanceDelta delta, Currency currency0, Currency currency1) internal {
        // Transfer tokens owed to the Pool Manager.
        if (delta.amount0() < 0) {
            POOL_MANAGER.sync(currency0);
            if (currency0.isAddressZero()) {
                POOL_MANAGER.settle{ value: uint128(-delta.amount0()) }();
            } else {
                currency0.transfer(address(POOL_MANAGER), uint128(-delta.amount0()));
                POOL_MANAGER.settle();
            }
        }
        if (delta.amount1() < 0) {
            POOL_MANAGER.sync(currency1);
            currency1.transfer(address(POOL_MANAGER), uint128(-delta.amount1()));
            POOL_MANAGER.settle();
        }

        // Withdraw tokens that the Pool Manager owes.
        if (delta.amount0() > 0) {
            POOL_MANAGER.take(currency0, (address(this)), uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            POOL_MANAGER.take(currency1, address(this), uint128(delta.amount1()));
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
    ) internal override {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));
        if (router == strategyHook[msg.sender]) revert InvalidRouter();

        // Handle pools with native ETH.
        address token0 = position.tokens[0];
        bool isNative = token0 == address(0);
        if (zeroToOne && isNative) {
            token0 = WETH;
            IWETH(WETH).deposit{ value: amountIn }();
        }

        // Approve token to swap.
        ERC20(zeroToOne ? token0 : position.tokens[1]).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPriceX96 might have moved and brought the pool out of balance.
        // By fetching the sqrtPriceX96, the transaction will revert in that case on the balance check.
        position.sqrtPriceX96 = _getSqrtPriceX96(position);

        // Handle pools with native ETH.
        if (isNative) IWETH(WETH).withdraw(ERC20(WETH).balanceOf(address(this)));

        // Update the balances, token0 might be native ETH.
        balances[0] = Currency.wrap(position.tokens[0]).balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param cache A struct with cached variables.
     */
    function _mint(
        uint256[] memory balances,
        Rebalancer.InitiatorParams memory,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) internal override {
        // Check it token0 is native ETH.
        bool isNative = position.tokens[0] == address(0);

        // Handle approvals.
        if (!isNative) _checkAndApprovePermit2(position.tokens[0]);
        _checkAndApprovePermit2(position.tokens[1]);

        // Get new token id.
        position.id = POSITION_MANAGER.nextTokenId();

        // Calculate liquidity to be added.
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(position.tokens[0]),
            Currency.wrap(position.tokens[1]),
            position.fee,
            position.tickSpacing,
            IHooks(position.pool)
        );
        // ToDo: move to swap?
        (position.sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(poolKey.toId());
        position.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(position.sqrtPriceX96), cache.sqrtRatioLower, cache.sqrtRatioUpper, balances[0], balances[1]
        );

        // Generate calldata to mint new position.
        bytes memory actions = new bytes(3);
        actions[0] = bytes1(uint8(Actions.MINT_POSITION));
        actions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
        actions[2] = bytes1(uint8(Actions.SWEEP));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            poolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(this),
            ""
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, address(this));

        // Mint the new position.
        uint256 ethValue = isNative ? balances[0] : 0;
        bytes memory mintParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities{ value: ethValue }(mintParams, block.timestamp);

        // Update the balances, token0 might be native ETH.
        balances[0] = Currency.wrap(position.tokens[0]).balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));

        // If token0 is in native ETH, wrap it.
        if (isNative) {
            position.tokens[0] = WETH;
            IWETH(payable(WETH)).deposit{ value: balances[0] }();
        }
    }

    /**
     * @notice Ensures that the Permit2 contract has sufficient approval to spend a given token.
     * @param token The contract address of the token.
     */
    function _checkAndApprovePermit2(address token) internal {
        if (!approved[token]) {
            approved[token] = true;
            ERC20(token).safeApproveWithRetry(address(PERMIT_2), type(uint256).max);
            PERMIT_2.approve(token, address(POSITION_MANAGER), type(uint160).max, type(uint48).max);
        }
    }
}
