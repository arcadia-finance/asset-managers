/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CompounderUniswapV4_Fuzz_Test } from "./_CompounderUniswapV4.fuzz.t.sol";
import { CompounderUniswapV4Extension } from "../../../../utils/extensions/CompounderUniswapV4Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CompounderUniswapV4".
 */
contract Constructor_CompounderUniswapV4_Fuzz_Test is CompounderUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        CompounderUniswapV4Extension compounder_ = new CompounderUniswapV4Extension(
            owner_,
            arcadiaFactory,
            routerTrampoline_,
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );

        assertEq(compounder_.owner(), owner_);
    }
}
