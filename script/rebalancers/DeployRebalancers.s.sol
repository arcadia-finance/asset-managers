/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Arcadia, Deployers, Slipstream, UniswapV3, UniswapV4 } from "../utils/ConstantsBase.sol";
import { Base_AssetManagers_Script } from "../Base.s.sol";
import { RebalancerSlipstream } from "../../src/rebalancers/RebalancerSlipstream.sol";
import { RebalancerUniswapV3 } from "../../src/rebalancers/RebalancerUniswapV3.sol";
import { RebalancerUniswapV4 } from "../../src/rebalancers/RebalancerUniswapV4.sol";

contract DeployRebalancers is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == Deployers.ARCADIA, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        new RebalancerSlipstream(
            Arcadia.FACTORY,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Slipstream.AERO,
            Arcadia.STAKED_SLIPSTREAM_AM,
            Arcadia.WRAPPED_STAKED_SLIPSTREAM
        );
        new RebalancerUniswapV3(Arcadia.FACTORY, UniswapV3.POSITION_MANAGER, UniswapV3.FACTORY);
        new RebalancerUniswapV4(
            Arcadia.FACTORY, UniswapV4.POSITION_MANAGER, UniswapV4.PERMIT_2, UniswapV4.POOL_MANAGER, UniswapV4.WETH
        );
        vm.stopBroadcast();
    }

    function test_deploy() public {
        vm.skip(true);
    }
}
