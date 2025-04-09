/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { SlipstreamLogic_Fuzz_Test } from "./_SlipstreamLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_computePoolAddress" of contract "SlipstreamLogic".
 */
contract ComputePoolAddress_SlipstreamLogic_Fuzz_Test is SlipstreamLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(SlipstreamLogic_Fuzz_Test) {
        SlipstreamLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_computePoolAddress(bytes32 salt0, bytes32 salt1) public {
        // Given: salts are not equal.
        vm.assume(salt0 != salt1);

        // And: Tokens are deployed.
        ERC20Mock token0 = new ERC20Mock{ salt: salt0 }("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock{ salt: salt1 }("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // When: Calling computePoolAddress().
        // Then: It correctly returns the pool address.
        int24[] memory TICK_SPACINGS = new int24[](4);
        TICK_SPACINGS[0] = 1;
        TICK_SPACINGS[1] = 50;
        TICK_SPACINGS[2] = 100;
        TICK_SPACINGS[3] = 200;
        for (uint256 i = 0; i < TICK_SPACINGS.length; ++i) {
            assertEq(
                slipstreamLogic.computePoolAddress(address(token0), address(token1), TICK_SPACINGS[i]),
                address(createPoolCL(address(token0), address(token1), TICK_SPACINGS[i], 1e18, 300))
            );
        }
    }
}
