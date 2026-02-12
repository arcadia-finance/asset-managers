/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserUniswapV4Extension } from "../../../../utils/extensions/CloserUniswapV4Extension.sol";
import { UniswapV4_Fuzz_Test } from "../../base/UniswapV4/_UniswapV4.fuzz.t.sol";

/**
 * @notice Common logic needed by all "CloserUniswapV4" fuzz tests.
 */
abstract contract CloserUniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_CLAIM_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CloserUniswapV4Extension internal closer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV4_Fuzz_Test) {
        UniswapV4_Fuzz_Test.setUp();

        // Deploy test contract.
        closer = new CloserUniswapV4Extension(
            users.owner,
            address(factory),
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );
    }
}
