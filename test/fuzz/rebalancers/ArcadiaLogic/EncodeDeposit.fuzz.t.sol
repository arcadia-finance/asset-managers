/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ActionData } from "../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic_Fuzz_Test } from "./_ArcadiaLogic.fuzz.t.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";

/**
 * @notice Fuzz tests for the function "_encodeDeposit" of contract "ArcadiaLogic".
 */
contract EncodeDeposit_ArcadiaLogic_Fuzz_Test is ArcadiaLogic_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        ArcadiaLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_encodeDeposit(
        address positionManager,
        uint256 id,
        Rebalancer.PositionState memory position,
        uint256 balance0,
        uint256 balance1,
        uint256 reward
    ) public {
        // Given: Correct count.
        uint256 count = 1;
        if (balance0 > 0) ++count;
        if (balance1 > 0) ++count;
        if (reward > 0) ++count;

        // When: calling _encodeDeposit().
        ActionData memory depositData =
            arcadiaLogic.encodeDeposit(positionManager, id, position, count, balance0, balance1, reward);

        // Then: It should return the correct arrays.
        assertEq(depositData.assets.length, count);
        assertEq(depositData.assetIds.length, count);
        assertEq(depositData.assetAmounts.length, count);
        assertEq(depositData.assetTypes.length, count);

        // And: Asset 0 should be the correct asset.
        assertEq(depositData.assets[0], positionManager);
        assertEq(depositData.assetIds[0], id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        uint256 index = 1;

        // And: Asset 1 should be the correct asset.
        if (balance0 > 0) {
            assertEq(depositData.assets[1], position.token0);
            assertEq(depositData.assetIds[1], 0);
            assertEq(depositData.assetAmounts[1], balance0);
            assertEq(depositData.assetTypes[1], 1);
            ++index;
        }

        // And: Asset 2 should be the correct asset.
        if (balance1 > 0) {
            assertEq(depositData.assets[index], position.token1);
            assertEq(depositData.assetIds[index], 0);
            assertEq(depositData.assetAmounts[index], balance1);
            assertEq(depositData.assetTypes[index], 1);
            ++index;
        }

        // And: Asset 3 should be the correct asset.
        if (reward > 0) {
            assertEq(depositData.assets[index], 0x940181a94A35A4569E4529A3CDfB74e38FD98631);
            assertEq(depositData.assetIds[index], 0);
            assertEq(depositData.assetAmounts[index], reward);
            assertEq(depositData.assetTypes[index], 1);
        }
    }
}
