/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AbstractBase } from "./AbstractBase.sol";
import { Actions } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/Actions.sol";
import { BalanceDelta } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { CLMath } from "../libraries/CLMath.sol";
import { Currency } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IHooks } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { IPermit2 } from "../rebalancers/interfaces/IPermit2.sol";
import { IPoolManager } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { IPositionManagerV4 } from "../rebalancers/interfaces/IPositionManagerV4.sol";
import { IWETH } from "../rebalancers/interfaces/IWETH.sol";
import { LiquidityAmounts } from "../libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { PositionState } from "../state/PositionState.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { StateLibrary } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @title Base implementation for managing Uniswap V4 Liquidity Positions.
 */
abstract contract UniswapV4 is AbstractBase {
    using FixedPointMathLib for uint256;
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
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param permit2 The contract address of Permit2.
     * @param poolManager The contract address of the Uniswap v4 Pool Manager.
     * @param weth The contract address of WETH.
     */
    constructor(address positionManager, address permit2, address poolManager, address weth) {
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
    function isPositionManager(address positionManager) public view virtual override returns (bool) {
        return positionManager == address(POSITION_MANAGER);
    }

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the underlying assets of the pool.
     * param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return token0 The contract address of token0.
     * @return token1 The contract address of token1.
     */
    function _getUnderlyingTokens(address, uint256 id)
        internal
        view
        virtual
        override
        returns (address token0, address token1)
    {
        (PoolKey memory poolKey,) = POSITION_MANAGER.getPoolAndPositionInfo(id);
        token0 = Currency.unwrap(poolKey.currency0);
        token1 = Currency.unwrap(poolKey.currency1);

        // If token0 is in native ETH, we need to withdraw wrapped eth from the Account.
        if (token0 == address(0)) token0 = WETH;
    }

    /**
     * @notice Returns the position and pool related state.
     * param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(address, uint256 id)
        internal
        view
        virtual
        override
        returns (PositionState memory position)
    {
        // Positions have two underlying tokens.
        position.tokens = new address[](2);

        // Get data of the Liquidity Position.
        position.id = id;
        (PoolKey memory poolKey, PositionInfo info) = POSITION_MANAGER.getPoolAndPositionInfo(id);
        position.tickLower = info.tickLower();
        position.tickUpper = info.tickUpper();
        bytes32 positionId =
            keccak256(abi.encodePacked(address(POSITION_MANAGER), info.tickLower(), info.tickUpper(), bytes32(id)));
        position.liquidity = POOL_MANAGER.getPositionLiquidity(poolKey.toId(), positionId);

        // Get data of the Liquidity Pool.
        position.pool = address(poolKey.hooks);
        position.tokens[0] = Currency.unwrap(poolKey.currency0);
        position.tokens[1] = Currency.unwrap(poolKey.currency1);
        position.fee = poolKey.fee;
        position.tickSpacing = poolKey.tickSpacing;
        (position.sqrtPrice, position.tickCurrent,,) = POOL_MANAGER.getSlot0(poolKey.toId());
    }

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(PositionState memory position)
        internal
        view
        virtual
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
     * @notice Returns the sqrtPrice of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPrice The sqrtPrice of the Pool.
     */
    function _getSqrtPrice(PositionState memory position) internal view virtual override returns (uint160 sqrtPrice) {
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(position.tokens[0]),
            Currency.wrap(position.tokens[1]),
            position.fee,
            position.tickSpacing,
            IHooks(position.pool)
        );
        (sqrtPrice,,,) = POOL_MANAGER.getSlot0(poolKey.toId());
    }

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @dev Must update the balances after the claim.
     */
    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address,
        PositionState memory position,
        uint256 claimFee
    ) internal virtual override {
        // Cache the currencies.
        Currency currency0 = Currency.wrap(position.tokens[0]);
        Currency currency1 = Currency.wrap(position.tokens[1]);

        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(position.id, 0, 0, 0, "");
        params[1] = abi.encode(currency0, currency1, address(this));

        bytes memory decreaseLiquidityParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities(decreaseLiquidityParams, block.timestamp);

        // Get the balances, token0 might be native ETH.
        uint256 balance0 = currency0.balanceOfSelf();
        uint256 balance1 = ERC20(position.tokens[1]).balanceOf(address(this));

        // Calculate claim fees.
        fees[0] += (balance0 - balances[0]).mulDivDown(claimFee, 1e18);
        fees[1] += (balance1 - balances[1]).mulDivDown(claimFee, 1e18);

        // Update the balances.
        balances[0] = balance0;
        balances[1] = balance1;
    }

    /* ///////////////////////////////////////////////////////////////
                          UNSTAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Unstakes a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _unstake(uint256[] memory balances, address, PositionState memory position) internal virtual override {
        // If token0 is in native ETH, and weth was withdrawn from the account, unwrap it.
        if (position.tokens[0] == address(0)) {
            uint256 wethBalance = ERC20(WETH).balanceOf(address(this));
            if (wethBalance > 0) {
                IWETH(WETH).withdraw(wethBalance);
                balances[0] += wethBalance;
            }
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _burn(uint256[] memory balances, address, PositionState memory position) internal virtual override {
        // Cache the currencies.
        Currency currency0 = Currency.wrap(position.tokens[0]);
        Currency currency1 = Currency.wrap(position.tokens[1]);

        // Generate calldata to burn the position and collect the underlying assets.
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.BURN_POSITION));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(position.id, 0, 0, "");
        params[1] = abi.encode(currency0, currency1, address(this));

        bytes memory burnParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities(burnParams, block.timestamp);

        // Update the balances, token0 might be native ETH.
        balances[0] = currency0.balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        virtual
        override
    {
        // Do the swap.
        bytes memory swapData = abi.encode(
            IPoolManager.SwapParams({
                zeroForOne: zeroToOne,
                amountSpecified: int256(amountOut),
                sqrtPriceLimitX96: zeroToOne ? CLMath.MIN_SQRT_PRICE_LIMIT : CLMath.MAX_SQRT_PRICE_LIMIT
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

        // Update the balances.
        BalanceDelta swapDelta = abi.decode(results, (BalanceDelta));
        balances[0] = zeroToOne
            ? balances[0] - uint256(-int256(swapDelta.amount0()))
            : balances[0] + uint256(int256(swapDelta.amount0()));
        balances[1] = zeroToOne
            ? balances[1] + uint256(int256(swapDelta.amount1()))
            : balances[1] - uint256(-int256(swapDelta.amount1()));
    }

    /**
     * @notice Callback function executed during the unlock phase of a Uniswap V4 pool operation.
     * @param data The encoded swap parameters and pool key.
     * @return results The encoded BalanceDelta result from the swap operation.
     */
    function unlockCallback(bytes calldata data) external payable virtual returns (bytes memory results) {
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

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to mint as liquidity.
     * @param amount1Desired The desired amount of token1 to mint as liquidity.
     */
    function _mint(
        uint256[] memory balances,
        address,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual override {
        // Check if token0 is native ETH.
        bool isNative = position.tokens[0] == address(0);

        // Handle approvals.
        if (!isNative) _checkAndApprovePermit2(position.tokens[0]);
        _checkAndApprovePermit2(position.tokens[1]);

        // Get new token id.
        position.id = POSITION_MANAGER.nextTokenId();

        // Calculate liquidity to be added.
        position.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            amount0Desired,
            amount1Desired
        );

        // Cache the pool key.
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(position.tokens[0]),
            Currency.wrap(position.tokens[1]),
            position.fee,
            position.tickSpacing,
            IHooks(position.pool)
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
        uint256 ethValue = isNative ? amount0Desired : 0;
        bytes memory mintParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities{ value: ethValue }(mintParams, block.timestamp);

        // Update the balances, token0 might be native ETH.
        balances[0] = poolKey.currency0.balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        address,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual override {
        // Check if token0 is native ETH.
        bool isNative = position.tokens[0] == address(0);

        // Handle approvals.
        if (!isNative) _checkAndApprovePermit2(position.tokens[0]);
        _checkAndApprovePermit2(position.tokens[1]);

        // Calculate liquidity to be added.
        position.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            amount0Desired,
            amount1Desired
        );

        // Cache the currencies.
        Currency currency0 = Currency.wrap(position.tokens[0]);
        Currency currency1 = Currency.wrap(position.tokens[1]);

        // Generate calldata to mint new position.
        bytes memory actions = new bytes(3);
        actions[0] = bytes1(uint8(Actions.INCREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
        actions[2] = bytes1(uint8(Actions.SWEEP));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(position.id, position.liquidity, type(uint128).max, type(uint128).max, "");
        params[1] = abi.encode(currency0, currency1);
        params[2] = abi.encode(currency0, address(this));

        // Mint the new position.
        uint256 ethValue = isNative ? amount0Desired : 0;
        bytes memory increaseLiquidityParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities{ value: ethValue }(increaseLiquidityParams, block.timestamp);

        // Update the balances, token0 might be native ETH.
        balances[0] = currency0.balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }

    /* ///////////////////////////////////////////////////////////////
                          STAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Stakes a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _stake(uint256[] memory balances, address, PositionState memory position) internal virtual override {
        // If token0 is in native ETH, wrap it.
        if (position.tokens[0] == address(0)) {
            position.tokens[0] = WETH;
            IWETH(payable(WETH)).deposit{ value: balances[0] }();
        }
    }

    /* ///////////////////////////////////////////////////////////////
                               HELPERS
    /////////////////////////////////////////////////////////////// */

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
