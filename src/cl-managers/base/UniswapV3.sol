/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "./AbstractBase.sol";
import { IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";
import { CLMath } from "../libraries/CLMath.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";
import { PositionState } from "../state/PositionState.sol";
import { SafeApprove } from "../../libraries/SafeApprove.sol";

/**
 * @title Base implementation for managing Uniswap V3 Liquidity Positions.
 */
abstract contract UniswapV3 is AbstractBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Uniswap v3 Position Manager.
    IPositionManagerV3 internal immutable POSITION_MANAGER;

    // The contract address of the Uniswap v3 Factory.
    address internal immutable UNISWAP_V3_FACTORY;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error OnlyPool();

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(address positionManager, address uniswapV3Factory) {
        POSITION_MANAGER = IPositionManagerV3(positionManager);
        UNISWAP_V3_FACTORY = uniswapV3Factory;
    }

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of Uniswap v3.
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
        (,, token0, token1,,,,,,,,) = POSITION_MANAGER.positions(id);
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
        (
                ,,
                position.tokens[0],
                position.tokens[1],
                position.fee,
                position.tickLower,
                position.tickUpper,
                position.liquidity,,,,
            ) = POSITION_MANAGER.positions(id);

        // Get data of the Liquidity Pool.
        position.pool =
            PoolAddress.computeAddress(UNISWAP_V3_FACTORY, position.tokens[0], position.tokens[1], position.fee);
        (position.sqrtPrice, position.tickCurrent,,,,,) = IUniswapV3Pool(position.pool).slot0();
        position.tickSpacing = IUniswapV3Pool(position.pool).tickSpacing();
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
        liquidity = IUniswapV3Pool(position.pool).liquidity();
    }

    /**
     * @notice Returns the sqrtPrice of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPrice The sqrtPrice of the Pool.
     */
    function _getSqrtPrice(PositionState memory position) internal view virtual override returns (uint160 sqrtPrice) {
        (sqrtPrice,,,,,,) = IUniswapV3Pool(position.pool).slot0();
    }

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param claimFee The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     */
    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address,
        PositionState memory position,
        uint256 claimFee
    ) internal virtual override {
        // We assume that the amount of tokens to collect never exceeds type(uint128).max.
        (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(
            IPositionManagerV3.CollectParams({
                tokenId: position.id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        balances[0] += amount0;
        balances[1] += amount1;

        // Calculate claim fees.
        fees[0] += amount0.mulDivDown(claimFee, 1e18);
        fees[1] += amount1.mulDivDown(claimFee, 1e18);

        emit YieldClaimed(msg.sender, position.tokens[0], amount0);
        emit YieldClaimed(msg.sender, position.tokens[1], amount1);
    }

    /* ///////////////////////////////////////////////////////////////
                          STAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Stakes a Liquidity Position.
     * param balances The balances of the underlying tokens.
     * param positionManager The contract address of the Position Manager.
     * param position A struct with position and pool related variables.
     */
    function _stake(uint256[] memory, address, PositionState memory) internal virtual override { }

    /**
     * @notice Unstakes a Liquidity Position.
     * param balances The balances of the underlying tokens.
     * param positionManager The contract address of the Position Manager.
     * param position A struct with position and pool related variables.
     */
    function _unstake(uint256[] memory, address, PositionState memory) internal virtual override { }

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @dev Does not emit YieldClaimed event, if necessary first call _claim() to emit the event before unstaking.
     */
    function _burn(uint256[] memory balances, address, PositionState memory position) internal virtual override {
        // Remove liquidity of the position and claim outstanding fees.
        _decreaseLiquidity(balances, address(0), position, position.liquidity);

        // Burn the position.
        POSITION_MANAGER.burn(position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                    DECREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Decreases liquidity of the Liquidity Position.
     * @param balances The balances of the underlying tokens.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param liquidity The amount of liquidity to decrease.
     * @dev Must update the balances and delta liquidity after the increase.
     */
    function _decreaseLiquidity(uint256[] memory balances, address, PositionState memory position, uint128 liquidity)
        internal
        virtual
        override
    {
        // Decrease liquidity of the position and claim outstanding fees.
        POSITION_MANAGER.decreaseLiquidity(
            IPositionManagerV3.DecreaseLiquidityParams({
                tokenId: position.id, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            })
        );

        // We assume that the amount of tokens to collect never exceeds type(uint128).max.
        (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(
            IPositionManagerV3.CollectParams({
                tokenId: position.id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        balances[0] += amount0;
        balances[1] += amount1;
    }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     */
    // forge-lint: disable-next-item(unsafe-typecast)
    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        virtual
        override
    {
        // Do the swap.
        (int256 deltaAmount0, int256 deltaAmount1) = IUniswapV3Pool(position.pool)
            .swap(
                address(this),
                zeroToOne,
                -int256(amountOut),
                zeroToOne ? CLMath.MIN_SQRT_PRICE_LIMIT : CLMath.MAX_SQRT_PRICE_LIMIT,
                abi.encode(position.tokens[0], position.tokens[1], position.fee)
            );

        // Update the balances.
        balances[0] = zeroToOne ? balances[0] - uint256(deltaAmount0) : balances[0] + uint256(-deltaAmount0);
        balances[1] = zeroToOne ? balances[1] + uint256(-deltaAmount1) : balances[1] - uint256(deltaAmount1);
    }

    /**
     * @notice Callback after executing a swap via IUniswapV3Pool.swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the position.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the position.
     * @param data Any data passed by this contract via the IUniswapV3Pool.swap() call.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external virtual {
        // Check that callback came from an actual Uniswap V3 Pool.
        (address token0, address token1, uint24 fee) = abi.decode(data, (address, address, uint24));

        if (PoolAddress.computeAddress(UNISWAP_V3_FACTORY, token0, token1, fee) != msg.sender) revert OnlyPool();

        // forge-lint: disable-next-item(unsafe-typecast)
        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens.
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
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), amount0Desired);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), amount1Desired);

        uint256 amount0;
        uint256 amount1;
        (position.id, position.liquidity, amount0, amount1) = POSITION_MANAGER.mint(
            IPositionManagerV3.MintParams({
                token0: position.tokens[0],
                token1: position.tokens[1],
                fee: position.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        balances[0] -= amount0;
        balances[1] -= amount1;
    }

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Increases liquidity of the Liquidity Position.
     * @param balances The balances of the underlying tokens.
     * param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        address,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual override {
        ERC20(position.tokens[0]).safeApproveWithRetry(address(POSITION_MANAGER), amount0Desired);
        ERC20(position.tokens[1]).safeApproveWithRetry(address(POSITION_MANAGER), amount1Desired);

        uint256 amount0;
        uint256 amount1;
        (position.liquidity, amount0, amount1) = POSITION_MANAGER.increaseLiquidity(
            IPositionManagerV3.IncreaseLiquidityParams({
                tokenId: position.id,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        balances[0] -= amount0;
        balances[1] -= amount1;
    }
}
