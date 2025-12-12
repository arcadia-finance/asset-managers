/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { YieldClaimerUniswapV3_Fuzz_Test } from "./_YieldClaimerUniswapV3.fuzz.t.sol";
import { YieldClaimerUniswapV3Extension } from "../../../../utils/extensions/YieldClaimerUniswapV3Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimerUniswapV3".
 */
contract Constructor_YieldClaimerUniswapV3_Fuzz_Test is YieldClaimerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        YieldClaimerUniswapV3Extension yieldClaimer_ = new YieldClaimerUniswapV3Extension(
            owner_, arcadiaFactory, address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        assertEq(yieldClaimer_.owner(), owner_);
    }
}
