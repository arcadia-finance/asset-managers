/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

// A struct with the position and pool state.
struct PositionState {
    // The contract address of the pool.
    address pool;
    // The id of the position.
    uint256 id;
    // The fee of the pool
    uint24 fee;
    // The tick spacing of the pool.
    int24 tickSpacing;
    // The current tick of the pool.
    int24 tickCurrent;
    // The lower tick of the position.
    int24 tickUpper;
    // The upper tick of the position.
    int24 tickLower;
    // The liquidity of the position.
    uint128 liquidity;
    // The sqrtPrice of the pool.
    uint256 sqrtPrice;
    // The underlying tokens of the pool.
    address[] tokens;
}
