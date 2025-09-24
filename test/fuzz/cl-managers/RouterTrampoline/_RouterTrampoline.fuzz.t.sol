/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { RouterTrampoline } from "../../../../src/cl-managers/RouterTrampoline.sol";

/**
 * @notice Common logic needed by all "RouterTrampoline" fuzz tests.
 */
abstract contract RouterTrampoline_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal tokenIn;
    ERC20Mock internal tokenOut;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RouterTrampoline internal routerTrampoline;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        // Create tokens.
        tokenIn = new ERC20Mock("TokenIn", "TOKI", 0);
        tokenOut = new ERC20Mock("TokenOut", "TOKO", 0);

        // Deploy test contract.
        routerTrampoline = new RouterTrampoline();
    }
}
