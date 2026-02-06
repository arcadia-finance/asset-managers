/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";

/**
 * @notice Fuzz tests for the function "approveToken" of contract "CowSwapper".
 */
contract ApproveToken_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error ApproveFailed();

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_approveToken_Reentered(address caller, address account_, address token) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // When: calling approveToken
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.approveToken(token);
    }

    function testFuzz_Revert_approveToken_NonToken(address caller, address nonToken) public {
        // Given: nonToken is not a token.
        vm.assume(nonToken != address(token0));
        vm.assume(nonToken != address(token1));

        // When: calling approveToken
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(ApproveFailed.selector);
        cowSwapper.approveToken(nonToken);
    }

    function testFuzz_Success_approveToken(address caller) public {
        // Given: Token is deployed.
        ERC20Mock token = new ERC20Mock("Token", "TKN", 18);

        // When: calling approveToken
        vm.prank(caller);
        cowSwapper.approveToken(address(token));

        // Then: The vault relayer is approved.
        assertEq(token.allowance(address(cowSwapper), address(vaultRelayer)), type(uint256).max);
    }

    function testFuzz_Success_approveToken_DoubleApproval(address caller) public {
        // Given: Token is deployed.
        ERC20Mock token = new ERC20Mock("Token", "TKN", 18);

        // When: calling approveToken twice.
        vm.startPrank(caller);
        cowSwapper.approveToken(address(token));
        cowSwapper.approveToken(address(token));
        vm.stopPrank();

        // Then: The vault relayer is approved.
        assertEq(token.allowance(address(cowSwapper), address(vaultRelayer)), type(uint256).max);
    }
}
