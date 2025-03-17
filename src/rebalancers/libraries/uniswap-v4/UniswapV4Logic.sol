/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IPermit2 } from "../../interfaces/IPermit2.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IPositionManagerV4 } from "../../interfaces/IPositionManagerV4.sol";
import { IStateView } from "../../interfaces/IStateView.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { RebalancerUniswapV4 } from "../../RebalancerUniswapV4.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

library UniswapV4Logic {
    using SafeTransferLib for ERC20;

    // The Uniswap V4 PoolManager contract.
    IPoolManager internal constant POOL_MANAGER = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
    // The Uniswap V4 PositionManager contract.
    IPositionManagerV4 internal constant POSITION_MANAGER =
        IPositionManagerV4(0x7C5f5A4bBd8fD63184577525326123B519429bDc);
    // The Uniswap V4 StateView contract.
    // TODO: Check why getSlot0 fails (StateLibrary not implemented on PoolManager).
    IStateView internal constant STATE_VIEW = IStateView(0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71);
    // The Permit2 contract.
    IPermit2 internal constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Actions used by the Uniswap V4 PositionManager.
    uint256 internal constant MINT_POSITION = 0x02;
    uint256 internal constant BURN_POSITION = 0x03;
    uint256 internal constant SETTLE_PAIR = 0x0d;
    uint256 internal constant TAKE_PAIR = 0x11;

    /**
     * @notice Fetches Uniswap V3 specific position data from external contracts.
     * @param position Struct with the position data.
     * @param id The id of the Liquidity Position.
     * @return tickCurrent The current tick of the pool.
     * @return tickRange The tick range of the position.
     */
    function _getPositionState(RebalancerUniswapV4.PositionState memory position, uint256 id)
        internal
        view
        returns (int24 tickCurrent, int24 tickRange)
    {
        // Get data of the Liquidity Position.
        (PoolKey memory poolKey, PositionInfo info) = POSITION_MANAGER.getPoolAndPositionInfo(id);
        position.token0 = Currency.unwrap(poolKey.currency0);
        position.token1 = Currency.unwrap(poolKey.currency1);
        position.tickSpacing = poolKey.tickSpacing;
        position.fee = poolKey.fee;
        position.hook = address(poolKey.hooks);
        bytes32 positionId =
            keccak256(abi.encodePacked(address(POSITION_MANAGER), info.tickLower(), info.tickUpper(), bytes32(id)));
        position.liquidity = STATE_VIEW.getPositionLiquidity(poolKey.toId(), positionId);
        tickRange = info.tickUpper() - info.tickLower();

        // Get data of the Liquidity Pool.
        (position.sqrtPriceX96, tickCurrent,,) = STATE_VIEW.getSlot0(poolKey.toId());
    }

    /**
     * @notice Processes token balance changes resulting from a swap operation
     * @dev Handles token transfers between the contract and the Pool Manager based on delta values:
     *      - For tokens owed to the Pool Manager: transfers tokens and calls settle()
     *      - For tokens owed from the Pool Manager: calls take() to receive tokens
     * @param delta The BalanceDelta containing the positive/negative changes in token amounts
     * @param currency0 The address of the first token in the pair
     * @param currency1 The address of the second token in the pair
     */
    function _processSwapDelta(BalanceDelta delta, Currency currency0, Currency currency1) internal {
        if (delta.amount0() < 0) {
            POOL_MANAGER.sync(currency0);
            currency0.transfer(address(POOL_MANAGER), uint128(-delta.amount0()));
            POOL_MANAGER.settle();
        }
        if (delta.amount1() < 0) {
            POOL_MANAGER.sync(currency1);
            currency1.transfer(address(POOL_MANAGER), uint128(-delta.amount1()));
            POOL_MANAGER.settle();
        }

        if (delta.amount0() > 0) {
            POOL_MANAGER.take(currency0, (address(this)), uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            POOL_MANAGER.take(currency1, address(this), uint128(delta.amount1()));
        }
    }

    /**
     * @notice Ensures that the Permit2 contract has sufficient approval to spend a given token
     * and grants unlimited approval to the PositionManager via Permit2.
     * @dev This function performs two key approval steps:
     *      1. Approves Permit2 to spend the specified token.
     *      2. Approves the PositionManager to spend the token through Permit2.
     * @dev If the token requires resetting the approval to zero before setting a new value,
     * this function first resets the approval to `0` before setting it to `type(uint256).max`.
     * @param token The address of the ERC20 token to approve.
     * @param amount The minimum amount required to be approved.
     */
    function _checkAndApprovePermit2(address token, uint256 amount) internal {
        uint256 currentAllowance =
            PERMIT_2.allowance(address(this), token, address(UniswapV4Logic.POSITION_MANAGER)).amount;

        if (currentAllowance < amount) {
            ERC20(token).safeApprove(address(PERMIT_2), 0);
            ERC20(token).safeApprove(address(PERMIT_2), type(uint256).max);
            PERMIT_2.approve(token, address(UniswapV4Logic.POSITION_MANAGER), type(uint160).max, type(uint48).max);
        }
    }
}
