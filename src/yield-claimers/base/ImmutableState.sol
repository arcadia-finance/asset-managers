/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { IFactory } from "../../interfaces/IFactory.sol";
import { IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";
import { IPositionManagerV4 } from "../interfaces/IPositionManagerV4.sol";
import { IWETH } from "../interfaces/IWETH.sol";

abstract contract ImmutableState {
    // The contract address of the Arcadia Factory.
    IFactory internal immutable FACTORY;

    // The contract address of reward token (AERO).
    address internal immutable REWARD_TOKEN;

    // The contract address of the Slipstream Position Manager.
    address internal immutable SLIPSTREAM_POSITION_MANAGER;

    // The contract address of the Staked Slipstream AM.
    address internal immutable STAKED_SLIPSTREAM_AM;

    // The contract address of the Staked Slipstream Wrapper.
    address internal immutable STAKED_SLIPSTREAM_WRAPPER;

    // The contract address of the Uniswap V3 Position Manager.
    address internal immutable UNISWAP_V3_POSITION_MANAGER;

    // The contract address of the Uniswap V4 Position Manager.
    IPositionManagerV4 internal immutable UNISWAP_V4_POSITION_MANAGER;

    // The contract address of WETH.
    IWETH internal immutable WETH;

    /**
     * @param factory The contract address of the Arcadia Factory.
     * @param rewardToken The contract address of the reward token for staked Slipstream positions (AERO).
     * @param slipstreamPositionManager The contract address of the Slipstream Position Manager.
     * @param stakedSlipstreamAM The contract address of the Staked Slipstream Asset Manager.
     * @param stakedSlipstreamWrapper The contract address of the Staked Slipstream Wrapper.
     * @param uniswapV3PositionManager The contract address of the Uniswap V3 Position Manager.
     * @param uniswapV4PositionManager The contract address of the Uniswap V4 Position Manager.
     * @param weth The contract address of WETH.
     */
    constructor(
        address factory,
        address rewardToken,
        address slipstreamPositionManager,
        address stakedSlipstreamAM,
        address stakedSlipstreamWrapper,
        address uniswapV3PositionManager,
        address uniswapV4PositionManager,
        address weth
    ) {
        FACTORY = IFactory(factory);
        REWARD_TOKEN = rewardToken;
        SLIPSTREAM_POSITION_MANAGER = slipstreamPositionManager;
        STAKED_SLIPSTREAM_AM = stakedSlipstreamAM;
        STAKED_SLIPSTREAM_WRAPPER = stakedSlipstreamWrapper;
        UNISWAP_V3_POSITION_MANAGER = uniswapV3PositionManager;
        UNISWAP_V4_POSITION_MANAGER = IPositionManagerV4(uniswapV4PositionManager);
        WETH = IWETH(weth);
    }
}
