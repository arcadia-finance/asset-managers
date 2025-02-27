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
}
