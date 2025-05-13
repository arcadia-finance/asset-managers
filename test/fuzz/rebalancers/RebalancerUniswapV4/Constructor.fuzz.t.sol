/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { RebalancerUniswapV4Extension } from "../../../utils/extensions/RebalancerUniswapV4Extension.sol";

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
    function testFuzz_Success_Constructor(
        address arcadiaFactory,
        uint256 maxFee,
        uint256 maxTolerance,
        uint256 maxSlippageRatio
    ) public {
        vm.prank(users.owner);
        RebalancerUniswapV4Extension rebalancer_ = new RebalancerUniswapV4Extension(
            arcadiaFactory,
            maxFee,
            maxTolerance,
            maxSlippageRatio,
            address(positionManagerV4),
            address(permit2),
            address(poolManager),
            address(weth9)
        );

        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(rebalancer_.MAX_TOLERANCE(), maxTolerance);
        assertEq(rebalancer_.MAX_FEE(), maxFee);
        assertEq(rebalancer_.MIN_LIQUIDITY_RATIO(), maxSlippageRatio);
    }
}
