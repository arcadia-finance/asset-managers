/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserUniswapV4_Fuzz_Test } from "./_CloserUniswapV4.fuzz.t.sol";
import { CloserUniswapV4Extension } from "../../../../utils/extensions/CloserUniswapV4Extension.sol";

/**
 * @notice Fuzz tests for the function "constructor" of contract "CloserUniswapV4".
 */
contract Constructor_CloserUniswapV4_Fuzz_Test is CloserUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        CloserUniswapV4Extension closer_ = new CloserUniswapV4Extension(
            owner_, arcadiaFactory, address(positionManagerV4), address(permit2), address(poolManager), address(weth9)
        );

        assertEq(closer_.owner(), owner_);
    }
}
