/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { SlipstreamCompounderHelper } from "../../src/compounders/slipstream/periphery/SlipstreamCompounderHelper.sol";
import { UniswapV3CompounderHelper } from "../../src/compounders/uniswap-v3/periphery/UniswapV3CompounderHelper.sol";

contract DeployCompoundersStep2 is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        slipstreamCompounderHelper = new SlipstreamCompounderHelper(address(slipstreamCompounder));
        uniswapV3CompounderHelper = new UniswapV3CompounderHelper(address(uniswapV3Compounder));
        vm.stopBroadcast();
    }
}
