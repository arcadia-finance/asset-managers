/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { Parameters } from "../utils/Constants.sol";
import { SlipstreamCompounder } from "../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { UniswapV3Compounder } from "../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";

contract DeployCompoundersStep1 is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        slipstreamCompounder =
            new SlipstreamCompounder(Parameters.COMPOUND_THRESHOLD, Parameters.INITIATOR_SHARE, Parameters.TOLERANCE);
        uniswapV3Compounder =
            new UniswapV3Compounder(Parameters.COMPOUND_THRESHOLD, Parameters.INITIATOR_SHARE, Parameters.TOLERANCE);
        vm.stopBroadcast();
    }
}
