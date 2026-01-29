/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";

/**
 * @notice Fuzz tests for the function "approveTokens" of contract "CowSwapper".
 */
contract ApproveTokens_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
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

    function testFuzz_Revert_approveTokens_Reentered(address caller, address account_, address[] memory tokens) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // When: calling approveTokens
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.approveTokens(tokens);
    }

    function testFuzz_Revert_approveTokens_NonToken(address caller, address[] memory nonTokens) public {
        // Given: Length of nonTokens is at least 1.
        vm.assume(nonTokens.length > 0);

        // And: First nonToken is not a token.
        vm.assume(nonTokens[0] != address(token0));
        vm.assume(nonTokens[0] != address(token1));

        // When: calling approveTokens
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(ApproveFailed.selector);
        cowSwapper.approveTokens(nonTokens);
    }

    function testFuzz_Success_approveTokens(address caller, uint8 length) public {
        // Given: Tokens are deployed.
        length = uint8(bound(length, 0, 10));
        address[] memory tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = address(new ERC20Mock("Token", "TKN", 18));
        }

        // When: calling approveTokens
        vm.prank(caller);
        cowSwapper.approveTokens(tokens);

        // Then: The vault relayer is approved.
        for (uint256 i = 0; i < length; i++) {
            assertEq(ERC20Mock(tokens[i]).allowance(address(cowSwapper), address(vaultRelayer)), type(uint256).max);
        }
    }

    function testFuzz_Success_approveTokens_DoubleApproval(address caller, uint8 length) public {
        // Given: Tokens are deployed.
        length = uint8(bound(length, 0, 10));
        address[] memory tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = address(new ERC20Mock("Token", "TKN", 18));
        }

        // When: calling approveTokens twice.
        vm.startPrank(caller);
        cowSwapper.approveTokens(tokens);
        cowSwapper.approveTokens(tokens);
        vm.stopPrank();

        // Then: The vault relayer is approved.
        for (uint256 i = 0; i < length; i++) {
            assertEq(ERC20Mock(tokens[i]).allowance(address(cowSwapper), address(vaultRelayer)), type(uint256).max);
        }
    }
}
