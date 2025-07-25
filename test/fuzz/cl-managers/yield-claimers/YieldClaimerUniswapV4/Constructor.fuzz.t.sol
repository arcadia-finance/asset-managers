/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimerUniswapV4_Fuzz_Test } from "./_YieldClaimerUniswapV4.fuzz.t.sol";
import { YieldClaimerUniswapV4Extension } from "../../../../utils/extensions/YieldClaimerUniswapV4Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimerUniswapV4".
 */
contract Constructor_YieldClaimerUniswapV4_Fuzz_Test is YieldClaimerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory) public {
        YieldClaimerUniswapV4Extension yieldClaimer_ = new YieldClaimerUniswapV4Extension(
            owner_, arcadiaFactory, address(positionManagerV4), address(permit2), address(poolManager), address(weth9)
        );

        assertEq(yieldClaimer_.owner(), owner_);
        assertEq(address(yieldClaimer_.ARCADIA_FACTORY()), arcadiaFactory);
    }
}
