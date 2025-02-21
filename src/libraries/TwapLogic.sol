/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { ICLPool } from "../interfaces/ICLPool.sol";

library TwapLogic {
    // The Number of seconds in the past from which to calculate the time-weighted tick.
    uint32 public constant TWAT_INTERVAL = 5 minutes;

    /**
     * @notice Calculates the time weighted average tick over 300s.
     * @param pool The liquidity pool.
     * @return tick The time weighted average tick over 300s.
     * @dev We do not use the TWAT price to calculate the current value of the asset.
     * It is used only to ensure that the deposited Liquidity range and thus
     * the risk of exposure manipulation is acceptable.
     */
    function _getTwat(address pool) internal view returns (int24 tick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[1] = TWAT_INTERVAL; // We take a 5 minute time interval.

        (int56[] memory tickCumulatives,) = ICLPool(pool).observe(secondsAgos);

        tick = int24((tickCumulatives[0] - tickCumulatives[1]) / int32(TWAT_INTERVAL));
    }
}
