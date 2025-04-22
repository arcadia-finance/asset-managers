/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { YieldClaimer } from "../../../src/yield-routers/YieldClaimer.sol";

contract YieldClaimerExtension is YieldClaimer {
    constructor(
        address rewardToken,
        address slipstreamPositionManager,
        address stakedSlipstreamAM,
        address stakedSlipstreamWrapper,
        address uniswapV3PositionManager,
        address uniswapV4PositionManager,
        address weth,
        uint256 maxInitiatorFee
    )
        YieldClaimer(
            rewardToken,
            slipstreamPositionManager,
            stakedSlipstreamAM,
            stakedSlipstreamWrapper,
            uniswapV3PositionManager,
            uniswapV4PositionManager,
            weth,
            maxInitiatorFee
        )
    { }

    function setAccount(address account_) external {
        account = account_;
    }

    function getAccount() external view returns (address account_) {
        account_ = account;
    }
}
