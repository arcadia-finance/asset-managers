/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { RebalancerUniV3Slipstream } from "../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RebalancerParameters } from "../utils/Constants.sol";

contract DeployRebalancer is Base_AssetManagers_Script {
    RebalancerUniV3Slipstream internal rebalancer;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        rebalancer = new RebalancerUniV3Slipstream(
            RebalancerParameters.MAX_TOLERANCE,
            RebalancerParameters.MAX_INITIATOR_FEE,
            RebalancerParameters.MIN_LIQUIDITY_RATIO
        );
        vm.stopBroadcast();
    }
}
