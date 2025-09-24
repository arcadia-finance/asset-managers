/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { RebalancerUniswapV4Extension } from "../../../../utils/extensions/RebalancerUniswapV4Extension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerUniswapV4".
 */
contract Constructor_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        RebalancerUniswapV4Extension rebalancer_ = new RebalancerUniswapV4Extension(
            owner_,
            arcadiaFactory,
            routerTrampoline_,
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );

        assertEq(rebalancer_.owner(), owner_);
        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(rebalancer_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
