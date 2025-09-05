/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { YieldClaimerUniswapV4Extension } from "../../../../utils/extensions/YieldClaimerUniswapV4Extension.sol";
import { UniswapV4_Fuzz_Test } from "../../base/UniswapV4/_UniswapV4.fuzz.t.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "YieldClaimerUniswapV4" fuzz tests.
 */
abstract contract YieldClaimerUniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    YieldClaimerUniswapV4Extension internal yieldClaimer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV4_Fuzz_Test) {
        UniswapV4_Fuzz_Test.setUp();

        // Deploy test contract.
        yieldClaimer = new YieldClaimerUniswapV4Extension(
            users.owner,
            address(factory),
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );
    }
}
