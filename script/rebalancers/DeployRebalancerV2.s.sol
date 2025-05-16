/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { Rebalancer } from "../../src/rebalancers/Rebalancer.sol";
import { RebalancerParameters } from "../utils/ConstantsBase.sol";
import { RebalancerSpot } from "../../src/rebalancers/RebalancerSpot.sol";

contract DeployRebalancerV2 is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == 0x0f518becFC14125F23b8422849f6393D59627ddB, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        new Rebalancer(
            RebalancerParameters.MAX_TOLERANCE,
            RebalancerParameters.MAX_INITIATOR_FEE,
            RebalancerParameters.MIN_LIQUIDITY_RATIO
        );
        new RebalancerSpot(
            RebalancerParameters.MAX_TOLERANCE,
            RebalancerParameters.MAX_INITIATOR_FEE,
            RebalancerParameters.MIN_LIQUIDITY_RATIO
        );
        vm.stopBroadcast();
    }
}
