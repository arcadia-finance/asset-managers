/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { AlienBaseCompounder } from "../../src/compounders/alien-base/AlienBaseCompounder.sol";
import { CompounderParameters, Quoters } from "../utils/Constants.sol";
import { SlipstreamCompounderHelperV2 } from
    "../../src/compounders/slipstream/periphery/SlipstreamCompounderHelperV2.sol";
import { UniswapV3CompounderHelperV2 } from "../../src/compounders/uniswap-v3/periphery/UniswapV3CompounderHelperV2.sol";

contract DeployAlienBaseStep2 is Base_AssetManagers_Script {
    UniswapV3CompounderHelperV2 internal alienBaseCompounderHelper;
    SlipstreamCompounderHelperV2 internal slipstreamCompounderHelper;
    UniswapV3CompounderHelperV2 internal uniswapV3CompounderHelper;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        alienBaseCompounder = new AlienBaseCompounder(
            CompounderParameters.COMPOUND_THRESHOLD,
            CompounderParameters.INITIATOR_SHARE,
            CompounderParameters.TOLERANCE
        );
        alienBaseCompounderHelper = new UniswapV3CompounderHelperV2(address(alienBaseCompounder), Quoters.ALIEN_BASE);
        slipstreamCompounderHelper = new SlipstreamCompounderHelperV2(address(slipstreamCompounder), Quoters.SLIPSTREAM);
        uniswapV3CompounderHelper = new UniswapV3CompounderHelperV2(address(uniswapV3Compounder), Quoters.UNISWAP_V3);
        vm.stopBroadcast();
    }
}
