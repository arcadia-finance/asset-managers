/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiator" of contract "UniswapV4Compounder".
 */
contract SetInitiator_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiator_Reentered(
        address caller,
        address account_,
        address account__,
        address initiator_
    ) public {
        // Given: A rebalance is ongoing.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling compoundFees().
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(UniswapV4Compounder.Reentered.selector);
        compounder.setInitiator(account__, initiator_);
    }

    function testFuzz_Revert_setInitiator_NotAnAccount(address caller, address account_, address initiator_) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling compoundFees().
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(UniswapV4Compounder.NotAnAccount.selector);
        compounder.setInitiator(account_, initiator_);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator_) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the compounder.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(UniswapV4Compounder.OnlyAccountOwner.selector);
        compounder.setInitiator(address(account), initiator_);
    }

    function testFuzz_Success_setAccountInfo(address initiator_) public {
        // Given: account is a valid Arcadia Account
        // When: Owner calls setInitiator on the compounder
        vm.prank(account.owner());
        compounder.setInitiator(address(account), initiator_);

        // Then: Initiator should be set for that Account
        assertEq(compounder.accountToInitiator(address(account)), initiator_);
    }
}
