/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder } from "../../../src/auto-compounder/AutoCompounder.sol";

contract AutoCompounderExtension is AutoCompounder {
    constructor(int24 tolerance_, uint256 minUsdFeeValue, uint256 initiatorFee)
        AutoCompounder(tolerance_, minUsdFeeValue, initiatorFee)
    { }

    function getTrustedTick(uint256 priceToken0, uint256 priceToken1) public pure returns (int256 trustedTick) {
        trustedTick = _getTrustedTick(priceToken0, priceToken1);
    }

    function rebalanceFees(PositionState memory position, Fees memory fees) public returns (Fees memory fees_) {
        fees_ = _rebalanceFees(position, fees);
    }

    function swap(PositionState memory position, Fees memory fees, bool zeroToOne, int256 amountIn)
        public
        returns (Fees memory fees_)
    {
        fees_ = _swap(position, fees, zeroToOne, amountIn);
    }

    function getConstantAddresses()
        public
        pure
        returns (address nonfungiblePositionManager, address registry, address uniV3Factory, address factory)
    {
        nonfungiblePositionManager = address(NONFUNGIBLE_POSITION_MANAGER);
        registry = address(REGISTRY);
        uniV3Factory = UNI_V3_FACTORY;
        factory = address(FACTORY);
    }
}
