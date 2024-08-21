/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../../../../src/libraries/ArcadiaLogic.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "rebalancePosition" of contract "UniswapV3Rebalancer".
 */
contract RebalancePosition_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(0));
        // Given : account is not address(0)
        rebalancer.setAccount(account_);

        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.Reentered.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(account));
        // Given : account is not an Arcadia Account
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.NotAnAccount.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(account));
        // Given : account is not an Arcadia Account
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.NotAnAccount.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }
}
