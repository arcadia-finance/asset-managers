/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { CompounderParameters } from "../utils/Constants.sol";
import { SlipstreamCompounder } from "../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamCompounderHelper } from
    "../../src/compounders/periphery/libraries/margin-accounts/slipstream/SlipstreamCompounderHelper.sol";
import { UniswapV3Compounder } from "../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3CompounderHelper } from
    "../../src/compounders/periphery/libraries/margin-accounts/uniswap-v3/UniswapV3CompounderHelper.sol";

contract DeployCompounders is Base_AssetManagers_Script {
    SlipstreamCompounderHelper internal slipstreamCompounderHelper;
    UniswapV3CompounderHelper internal uniswapV3CompounderHelper;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        slipstreamCompounder = new SlipstreamCompounder(
            CompounderParameters.COMPOUND_THRESHOLD,
            CompounderParameters.INITIATOR_SHARE,
            CompounderParameters.TOLERANCE
        );
        slipstreamCompounderHelper = new SlipstreamCompounderHelper(address(slipstreamCompounder));

        uniswapV3Compounder = new UniswapV3Compounder(
            CompounderParameters.COMPOUND_THRESHOLD,
            CompounderParameters.INITIATOR_SHARE,
            CompounderParameters.TOLERANCE
        );
        uniswapV3CompounderHelper = new UniswapV3CompounderHelper(address(uniswapV3Compounder));
        vm.stopBroadcast();
    }
}
