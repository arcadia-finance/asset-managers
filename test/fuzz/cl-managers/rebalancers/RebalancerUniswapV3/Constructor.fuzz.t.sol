/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";
import { RebalancerUniswapV3Extension } from "../../../../utils/extensions/RebalancerUniswapV3Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerUniswapV3".
 */
contract Constructor_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address arcadiaFactory) public {
        vm.prank(users.owner);
        RebalancerUniswapV3Extension rebalancer_ = new RebalancerUniswapV3Extension(
            arcadiaFactory, address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
    }
}
