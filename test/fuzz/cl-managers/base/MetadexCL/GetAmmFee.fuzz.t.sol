/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IMockSwapHook } from "../../../../../lib/accounts-v2/test/utils/mocks/Metadex03/interfaces/IMockSwapHook.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "_getAmmFee" of contract "Slipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmmFee_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    using stdStorage for StdStorage;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmmFee_RevertingHook(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);
        PositionState memory position_ = base.getPositionState(address(metadex03PositionManager), position.id);

        // And: A reverting hook is set on the pool.
        IMockSwapHook swapHook = IMockSwapHook(deployCode("MockSwapHook.sol"));
        swapHook.setShouldRevert(true);
        setSwapHookMetadex03CL(address(poolCl), address(swapHook));

        // When: Calling getAmmFee.
        // Then: It reverts with the reason of the hook.
        vm.expectRevert(bytes("HOOK"));
        base.getAmmFee(position_);
    }

    function testFuzz_Success_getAmmFee(uint128 liquidityPool, PositionState memory position, uint24 ammFee) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);
        PositionState memory position_ = base.getPositionState(address(metadex03PositionManager), position.id);

        // And: The factory returns another fee since the position state was read.
        ammFee = uint24(bound(ammFee, 0, MAX_POOL_FEE));
        stdstore.target(address(metadex03CLFactory))
            .sig("tickSpacingToFee(int24)")
            .with_key(uint256(int256(position.tickSpacing)))
            .checked_write(ammFee);

        // When: Calling getAmmFee.
        uint24 ammFee_ = base.getAmmFee(position_);

        // Then: It returns the fee the AMM charges at the time of the call.
        assertEq(ammFee_, ammFee);
    }
}
