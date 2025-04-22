/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";
import { IPositionManagerV4 } from "../interfaces/IPositionManagerV4.sol";
import { IWETH } from "../interfaces/IWETH.sol";

abstract contract ImmutableState {
    // The address of reward token (AERO).
    address internal immutable REWARD_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // The address of the Slipstream Position Manager.
    address internal immutable SLIPSTREAM_POSITION_MANAGER = 0x827922686190790b37229fd06084350E74485b72;

    // The address of the Staked Slipstream AM.
    address internal immutable STAKED_SLIPSTREAM_AM = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;

    // The Wrapped Staked Slipstream Asset Module contract.
    address internal immutable STAKED_SLIPSTREAM_WRAPPER = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;

    // The address of the Uniswap V3 Position Manager.
    address internal immutable UNISWAP_V3_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    // The address of the Uniswap V4 Position Manager.
    IPositionManagerV4 internal immutable UNISWAP_V4_POSITION_MANAGER =
        IPositionManagerV4(0x7C5f5A4bBd8fD63184577525326123B519429bDc);

    // The address of WETH.
    IWETH internal immutable WETH;

    constructor(
        address rewardToken,
        address slipstreamPositionManager,
        address stakedSlipstreamAM,
        address stakedSlipstreamWrapper,
        address uniswapV3PositionManager,
        address uniswapV4PositionManager,
        address weth
    ) {
        REWARD_TOKEN = rewardToken;
        SLIPSTREAM_POSITION_MANAGER = slipstreamPositionManager;
        STAKED_SLIPSTREAM_AM = stakedSlipstreamAM;
        STAKED_SLIPSTREAM_WRAPPER = stakedSlipstreamWrapper;
        UNISWAP_V3_POSITION_MANAGER = uniswapV3PositionManager;
        UNISWAP_V4_POSITION_MANAGER = IPositionManagerV4(uniswapV4PositionManager);
        WETH = IWETH(weth);
    }
}
