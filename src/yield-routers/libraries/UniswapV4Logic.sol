/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { Actions } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/Actions.sol";
import { Currency } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { IPositionManagerV4 } from "../interfaces/IPositionManagerV4.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";

library UniswapV4Logic {
    // The Uniswap V4 PositionManager contract.
    IPositionManagerV4 internal constant POSITION_MANAGER =
        IPositionManagerV4(0x7C5f5A4bBd8fD63184577525326123B519429bDc);

    /**
     * @notice Collects fees for a specific liquidity position in a Uniswap V4 pool.
     * @param tokenId The id of the liquidity position in UniswapV4 PositionManager.
     * @param poolKey The key containing pool parameters.
     * @return feeAmount0 The amount of fees collected in terms of token0.
     * @return feeAmount1 The amount of fees collected in terms of token1.
     */
    function _collectFees(uint256 tokenId, PoolKey memory poolKey)
        internal
        returns (uint256 feeAmount0, uint256 feeAmount1)
    {
        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

        bytes memory decreaseLiquidityParams = abi.encode(actions, params);
        POSITION_MANAGER.modifyLiquidities(decreaseLiquidityParams, block.timestamp);

        feeAmount0 = poolKey.currency0.balanceOfSelf();
        feeAmount1 = poolKey.currency1.balanceOfSelf();
    }
}
