/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_Script } from "../lib/accounts-v2/script/Base.s.sol";

import { AlienBaseCompounder } from "../src/compounders/alien-base/AlienBaseCompounder.sol";
import { Compounders } from "./utils/ConstantsBase.sol";
import { SlipstreamCompounder } from "../src/compounders/slipstream/SlipstreamCompounder.sol";
import { UniswapV3Compounder } from "../src/compounders/uniswap-v3/UniswapV3Compounder.sol";

abstract contract Base_AssetManagers_Script is Base_Script {
    AlienBaseCompounder internal alienBaseCompounder = AlienBaseCompounder(Compounders.ALIEN_BASE);
    SlipstreamCompounder internal slipstreamCompounder = SlipstreamCompounder(Compounders.SLIPSTREAM);
    UniswapV3Compounder internal uniswapV3Compounder = UniswapV3Compounder(Compounders.UNISWAP_V3);

    constructor() {
        deployer = vm.envUint("PRIVATE_KEY_DEPLOYER");
    }
}
