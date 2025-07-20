/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CompounderUniswapV3_Fuzz_Test } from "./_CompounderUniswapV3.fuzz.t.sol";
import { CompounderUniswapV3Extension } from "../../../../utils/extensions/CompounderUniswapV3Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CompounderUniswapV3".
 */
contract Constructor_CompounderUniswapV3_Fuzz_Test is CompounderUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        CompounderUniswapV3Extension compounder_ = new CompounderUniswapV3Extension(
            owner_, arcadiaFactory, routerTrampoline_, address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        assertEq(compounder_.owner(), owner_);
        assertEq(address(compounder_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(compounder_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
