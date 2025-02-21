/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ICLPool } from "../interfaces/ICLPool.sol";
import { ICLPositionManager } from "../interfaces/ICLPositionManager.sol";
import { PoolAddress } from "./slipstream/PoolAddress.sol";
import { Rebalancer } from "../Rebalancer.sol";

library SlipstreamLogic {
    // The Slipstream Factory contract.
    address internal constant CL_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;

    // The Slipstream Pool Implementation contract.
    address internal constant POOL_IMPLEMENTATION = 0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831;

    // The Slipstream NonfungiblePositionManager contract.
    ICLPositionManager internal constant POSITION_MANAGER =
        ICLPositionManager(0x827922686190790b37229fd06084350E74485b72);

    /**
     * @notice Computes the contract address of a Slipstream Pool.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param tickSpacing The tick spacing of the Pool.
     * @return pool The contract address of the Slipstream Pool.
     */
    function _computePoolAddress(address token0, address token1, int24 tickSpacing)
        internal
        pure
        returns (address pool)
    {
        pool = PoolAddress.computeAddress(POOL_IMPLEMENTATION, CL_FACTORY, token0, token1, tickSpacing);
    }

    /**
     * @notice Fetches Slipstream specific position data from external contracts.
     * @param position Struct with the position data.
     * @param id The id of the Liquidity Position.
     * @return tickCurrent The current tick of the pool.
     * @return tickRange The tick range of the position.
     */
    function _getPositionState(Rebalancer.PositionState memory position, uint256 id)
        internal
        view
        returns (int24 tickCurrent, int24 tickRange)
    {
        // Get data of the Liquidity Position.
        int24 tickLower;
        int24 tickUpper;
        (,, position.token0, position.token1, position.tickSpacing, tickLower, tickUpper, position.liquidity,,,,) =
            POSITION_MANAGER.positions(id);
        tickRange = tickUpper - tickLower;

        // Get data of the Liquidity Pool.
        position.pool = _computePoolAddress(position.token0, position.token1, position.tickSpacing);
        (position.sqrtPriceX96, tickCurrent,,,,) = ICLPool(position.pool).slot0();

        position.fee = ICLPool(position.pool).fee();
    }
}
