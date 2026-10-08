/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    LPFeeLibrary
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/LPFeeLibrary.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getAmmFee" of contract "UniswapV4".
 */
contract GetAmmFee_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmmFee(
        uint128 liquidityPool,
        uint24 protocolFee,
        uint24 lpFee,
        PositionState memory position,
        bool native,
        uint64 amountOut
    ) public {
        // Given: A valid pool.
        (liquidityPool, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);

        // And: An lpFee up to the exact output limit.
        position.poolFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE - (protocolFee == 0 ? 1 : 2)));
        setPoolState(liquidityPool, position, protocolFee, native);

        // And: A valid position.
        givenValidPositionState(position);
        setPositionState(position);
        PositionState memory position_ = base.getPositionState(address(positionManagerV4), position.id);

        // And: A swap in the direction with the larger protocol fee.
        bool zeroToOne = (protocolFee & 0xfff) >= (protocolFee >> 12);
        {
            uint256 balanceOut = zeroToOne
                ? token1.balanceOf(address(poolManager))
                : native ? address(poolManager).balance : token0.balanceOf(address(poolManager));
            vm.assume(balanceOut >= 1e7);
            amountOut = uint64(bound(amountOut, 1, balanceOut / 1e7));
        }
        uint256[] memory balances = new uint256[](2);
        balances[0] = type(uint128).max;
        balances[1] = type(uint128).max;
        if (native) vm.deal(address(base), type(uint128).max);
        else deal(address(token0), address(base), type(uint128).max, true);
        deal(address(token1), address(base), type(uint128).max, true);
        vm.recordLogs();
        base.swapViaPool(balances, position_, zeroToOne, amountOut);
        (,, uint24 swapFee) = getSwap(vm.getRecordedLogs());

        // When: Calling getAmmFee.
        uint24 ammFee = base.getAmmFee(position_);

        // Then: It equals the fee of the swap.
        assertEq(ammFee, swapFee);
    }
}
