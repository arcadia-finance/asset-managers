// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.22;

interface ICLPool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}
