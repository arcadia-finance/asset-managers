// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.22;

/// @title Non-fungible token for positions
/// @notice Wraps Slipstream positions in a non-fungible token interface which allows for them to be transferred
/// and authorized.

interface ICLPositionManager {
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function approve(address spender, uint256 tokenId) external;

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}
