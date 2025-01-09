/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { TwapLogic } from "../../../src/libraries/TwapLogic.sol";

contract TwapLogicExtension {
    function getTwat(address pool) external returns (int24) {
        return TwapLogic._getTwat(pool);
    }
}
