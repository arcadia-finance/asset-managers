/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IPoolManager } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";

contract DynamicFeeHookMock {
    IPoolManager internal immutable POOL_MANAGER;

    constructor(IPoolManager poolManager) {
        POOL_MANAGER = poolManager;
    }

    function setLpFee(PoolKey memory poolKey, uint24 lpFee) external {
        POOL_MANAGER.updateDynamicLPFee(poolKey, lpFee);
    }
}
