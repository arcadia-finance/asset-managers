/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { Actions } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/Actions.sol";
import { Currency } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ImmutableState } from "./ImmutableState.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";

abstract contract UniswapV4Logic is ImmutableState {
    /**
     * @notice Claims fees from a Uniswap V4 Liquidity Position.
     * @param id The id of the Uniswap V4 Liquidity Position.
     * @return tokens The addresses of the fee tokens.
     * @return amounts The corresponding amounts of each token collected as fees.
     * @dev If token0 is native ETH, it is automatically wrapped into WETH.
     */
    function claimFees(uint256 id) internal returns (address[] memory tokens, uint256[] memory amounts) {
        (PoolKey memory poolKey,) = UNISWAP_V4_POSITION_MANAGER.getPoolAndPositionInfo(id);

        tokens = new address[](2);
        tokens[0] = Currency.unwrap(poolKey.currency0);
        tokens[1] = Currency.unwrap(poolKey.currency1);

        amounts = _claimFees(id, poolKey);

        // If token0 is native ETH, we convert ETH to WETH.
        if (tokens[0] == address(0)) {
            WETH.deposit{ value: amounts[0] }();
            tokens[0] = address(WETH);
        }
    }

    /**
     * @notice Claims fees for a specific liquidity position in a Uniswap V4 pool.
     * @param tokenId The id of the liquidity position in UniswapV4 PositionManager.
     * @param poolKey The key containing pool parameters.
     * @return amounts The amounts of fees claimed.
     */
    function _claimFees(uint256 tokenId, PoolKey memory poolKey) internal returns (uint256[] memory amounts) {
        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
        actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));

        bytes memory decreaseLiquidityParams = abi.encode(actions, params);
        UNISWAP_V4_POSITION_MANAGER.modifyLiquidities(decreaseLiquidityParams, block.timestamp);

        amounts = new uint256[](2);
        amounts[0] = poolKey.currency0.balanceOfSelf();
        amounts[1] = poolKey.currency1.balanceOfSelf();
    }
}
