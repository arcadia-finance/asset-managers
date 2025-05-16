/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { Rebalancer } from "../../src/rebalancers/Rebalancer.sol";
import { RebalancerParameters } from "../utils/ConstantsBase.sol";

contract DeployRebalancer is Base_AssetManagers_Script {
    Rebalancer internal rebalancer;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        rebalancer = new Rebalancer(
            RebalancerParameters.MAX_TOLERANCE,
            RebalancerParameters.MAX_INITIATOR_FEE,
            RebalancerParameters.MIN_LIQUIDITY_RATIO
        );
        vm.stopBroadcast();
    }
}
