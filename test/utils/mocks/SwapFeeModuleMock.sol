/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ICLPoolObservations {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );

    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
}

contract SwapFeeModuleMock {
    mapping(address pool => uint24 fee) internal fee;
    mapping(address pool => uint24 initialFee) internal initialFee;
    mapping(address pool => bool initialFeeEnabled) internal initialFeeEnabled;

    function setFee(address pool, uint24 fee_) external {
        fee[pool] = fee_;
    }

    function setInitialFee(address pool, uint24 initialFee_, bool initialFeeEnabled_) external {
        initialFee[pool] = initialFee_;
        initialFeeEnabled[pool] = initialFeeEnabled_;
    }

    function getFee(address pool) external view returns (uint24 fee_) {
        fee_ = fee[pool];
        if (initialFeeEnabled[pool]) {
            (,, uint16 observationIndex,,,) = ICLPoolObservations(pool).slot0();
            (uint32 lastObservationTimestamp,,,) = ICLPoolObservations(pool).observations(observationIndex);
            if (lastObservationTimestamp != uint32(block.timestamp)) fee_ = initialFee[pool];
        }
    }
}
