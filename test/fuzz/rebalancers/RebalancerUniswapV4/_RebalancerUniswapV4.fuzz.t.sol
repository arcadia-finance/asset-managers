/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV4Extension } from "../../../utils/extensions/RebalancerUniswapV4Extension.sol";
import { UniswapV4_Fuzz_Test } from "../../base/UniswapV4/_UniswapV4.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV4" fuzz tests.
 */
abstract contract RebalancerUniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerUniswapV4Extension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV4_Fuzz_Test) {
        UniswapV4_Fuzz_Test.setUp();

        // Deploy test contract.
        rebalancer = new RebalancerUniswapV4Extension(
            address(factory),
            MAX_FEE,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );
    }
}
