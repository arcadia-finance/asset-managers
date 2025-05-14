/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CompounderUniswapV4Extension } from "../../../utils/extensions/CompounderUniswapV4Extension.sol";
import { UniswapV4_Fuzz_Test } from "../../base/UniswapV4/_UniswapV4.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "CompounderUniswapV4" fuzz tests.
 */
abstract contract CompounderUniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CompounderUniswapV4Extension internal compounder;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV4_Fuzz_Test) {
        UniswapV4_Fuzz_Test.setUp();

        // Deploy test contract.
        compounder = new CompounderUniswapV4Extension(
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
