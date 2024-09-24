/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { ICLPositionManager } from "../interfaces/ICLPositionManager.sol";
import { PoolAddress } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/libraries/PoolAddress.sol";

library SlipstreamLogic {
    // The Slipstream Factory contract.
    address internal constant CL_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;

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
        view
        returns (address pool)
    {
        pool = PoolAddress.computeAddress(CL_FACTORY, token0, token1, tickSpacing);
    }
}
