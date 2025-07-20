/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV4Extension } from "../../../../utils/extensions/RebalancerUniswapV4Extension.sol";
import { RouterTrampoline } from "../../../../../src/cl-managers/RouterTrampoline.sol";
import { UniswapV4_Fuzz_Test } from "../../base/UniswapV4/_UniswapV4.fuzz.t.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV4" fuzz tests.
 */
abstract contract RebalancerUniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterTrampoline internal routerTrampoline;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerUniswapV4Extension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV4_Fuzz_Test) {
        UniswapV4_Fuzz_Test.setUp();

        // Deploy Router Trampoline.
        routerTrampoline = new RouterTrampoline();

        // Deploy test contract.
        vm.prank(users.owner);
        rebalancer = new RebalancerUniswapV4Extension(
            address(factory),
            address(routerTrampoline),
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );
    }
}
