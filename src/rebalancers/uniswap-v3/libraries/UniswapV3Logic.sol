/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { IUniswapV3PositionManager } from "../interfaces/IUniswapV3PositionManager.sol";
import { PoolAddress } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/PoolAddress.sol";

library UniswapV3Logic {
    // The Uniswap V3 Factory contract.
    address internal constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // The Uniswap V3 NonfungiblePositionManager contract.
    IUniswapV3PositionManager internal constant POSITION_MANAGER =
        IUniswapV3PositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);

    /**
     * @notice Computes the contract address of a Uniswap V3 Pool.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param fee The fee of the Pool.
     * @return pool The contract address of the Uniswap V3 Pool.
     */
    function _computePoolAddress(address token0, address token1, uint24 fee) internal pure returns (address pool) {
        pool = PoolAddress.computeAddress(UNISWAP_V3_FACTORY, token0, token1, fee);
    }
}
