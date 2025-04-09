/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { UniswapV3Logic_Fuzz_Test } from "./_UniswapV3Logic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_computePoolAddress" of contract "UniswapV3Logic".
 */
contract ComputePoolAddress_UniswapV3Logic_Fuzz_Test is UniswapV3Logic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(UniswapV3Logic_Fuzz_Test) {
        UniswapV3Logic_Fuzz_Test.setUp();
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
        uint24[] memory FEES = new uint24[](3);
        FEES[0] = 100;
        FEES[1] = 500;
        FEES[2] = 3000;
        for (uint256 i = 0; i < FEES.length; ++i) {
            assertEq(
                uniswapV3Logic.computePoolAddress(address(token0), address(token1), FEES[i]),
                address(createPoolUniV3(address(token0), address(token1), FEES[i], 1e18, 300))
            );
        }
    }
}
