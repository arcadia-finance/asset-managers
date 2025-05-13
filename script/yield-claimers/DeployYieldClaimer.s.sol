/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Base_AssetManagers_Script } from "../Base.s.sol";
import { Arcadia, Assets, PositionManagers, YieldClaimerParameters } from "../utils/Constants.sol";
import { YieldClaimer } from "../../src/yield-claimers/YieldClaimer.sol";

contract DeployYieldClaimer is Base_AssetManagers_Script {
    YieldClaimer internal yieldClaimer;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == 0x0f518becFC14125F23b8422849f6393D59627ddB, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        yieldClaimer = new YieldClaimer(
            Arcadia.FACTORY,
            Assets.AERO,
            PositionManagers.SLIPSTREAM,
            PositionManagers.STAKED_SLIPSTREAM,
            PositionManagers.WRAPPED_STAKED_SLIPSTREAM,
            PositionManagers.UNISWAP_V3,
            PositionManagers.UNISWAP_V4,
            Assets.WETH,
            YieldClaimerParameters.MAX_FEE
        );
        vm.stopBroadcast();
    }

    function test_deploy() public {
        vm.skip(true);
    }
}
