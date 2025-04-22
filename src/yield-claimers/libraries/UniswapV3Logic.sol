/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CollectParams, IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";

library UniswapV3Logic {
    /**
     * @notice Claims fees from a Uniswap V3 Liquidity Position.
     * @param positionManager The contract address of the Uniswap V3 Position Manager.
     * @param id The id of the Uniswap V3 Liquidity Position.
     * @return tokens The addresses of the fee tokens.
     * @return amounts The corresponding amounts of each token collected as fees.
     */
    function claimFees(address positionManager, uint256 id)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](2);
        amounts = new uint256[](2);
        (,, tokens[0], tokens[1],,,,,,,,) = IPositionManagerV3(positionManager).positions(id);
        (amounts[0], amounts[1]) = IPositionManagerV3(positionManager).collect(
            CollectParams({
                tokenId: id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }
}
