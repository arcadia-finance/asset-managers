/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PoolId } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";

interface IPoolManagerExtension {
    function setCurrentPrice(PoolId poolId, int24 tick, uint160 sqrtPrice) external;
}

contract RouterSetPoolPriceUniV4Mock {
    function swap(address poolManager, PoolId poolId, int24 tick, uint160 sqrtPrice) external {
        IPoolManagerExtension(poolManager).setCurrentPrice(poolId, tick, sqrtPrice);
    }
}
