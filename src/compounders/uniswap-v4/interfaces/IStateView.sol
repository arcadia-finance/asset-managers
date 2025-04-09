// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";

interface IStateView {
    /// @notice Get Slot0 of the pool: sqrtPriceX96, tick, protocolFee, lpFee
    /// @dev Corresponds to pools[poolId].slot0
    /// @param poolId The ID of the pool.
    /// @return sqrtPriceX96 The square root of the price of the pool, in Q96 precision.
    /// @return tick The current tick of the pool.
    /// @return protocolFee The protocol fee of the pool.
    /// @return lpFee The swap fee of the pool.
    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    /// @notice Retrieves the liquidity of a position.
    /// @dev Corresponds to pools[poolId].positions[positionId].liquidity. More gas efficient for just retrieving liquidity as compared to getPositionInfo
    /// @param poolId The ID of the pool.
    /// @param positionId The ID of the position.
    /// @return liquidity The liquidity of the position.
    function getPositionLiquidity(PoolId poolId, bytes32 positionId) external view returns (uint128 liquidity);

    /// @notice Retrieves the fee growth outside a tick range of a pool
    /// @dev Corresponds to pools[poolId].ticks[tick].feeGrowthOutside0X128 and pools[poolId].ticks[tick].feeGrowthOutside1X128. A more gas efficient version of getTickInfo
    /// @param poolId The ID of the pool.
    /// @param tick The tick to retrieve fee growth for.
    /// @return feeGrowthOutside0X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    /// @return feeGrowthOutside1X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    function getTickFeeGrowthOutside(PoolId poolId, int24 tick)
        external
        view
        returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128);

    /// @notice Calculate the fee growth inside a tick range of a pool
    /// @dev pools[poolId].feeGrowthInside0LastX128 in Position.Info is cached and can become stale. This function will calculate the up to date feeGrowthInside
    /// @param poolId The ID of the pool.
    /// @param tickLower The lower tick of the range.
    /// @param tickUpper The upper tick of the range.
    /// @return feeGrowthInside0X128 The fee growth inside the tick range for token0.
    /// @return feeGrowthInside1X128 The fee growth inside the tick range for token1.
    function getFeeGrowthInside(PoolId poolId, int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128);

    /// @notice Retrieves the position information of a pool at a specific position ID.
    /// @dev Corresponds to pools[poolId].positions[positionId]
    /// @param poolId The ID of the pool.
    /// @param positionId The ID of the position.
    /// @return liquidity The liquidity of the position.
    /// @return feeGrowthInside0LastX128 The fee growth inside the position for token0.
    /// @return feeGrowthInside1LastX128 The fee growth inside the position for token1.
    function getPositionInfo(PoolId poolId, bytes32 positionId)
        external
        view
        returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128);
}
