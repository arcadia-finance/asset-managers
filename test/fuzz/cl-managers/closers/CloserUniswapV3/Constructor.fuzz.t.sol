/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserUniswapV3_Fuzz_Test } from "./_CloserUniswapV3.fuzz.t.sol";
import { CloserUniswapV3Extension } from "../../../../utils/extensions/CloserUniswapV3Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CloserUniswapV3".
 */
contract Constructor_CloserUniswapV3_Fuzz_Test is CloserUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        CloserUniswapV3Extension closer_ = new CloserUniswapV3Extension(
            owner_, arcadiaFactory, address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        assertEq(closer_.owner(), owner_);
    }
}
