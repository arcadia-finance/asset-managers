/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >=0.6.2;
pragma experimental ABIEncoderV2;

import { Test } from "../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { NonfungiblePositionManagerExtension } from
    "../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/NonfungiblePositionManagerExtension.sol";
import { QuoterV2 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/lens/QuoterV2.sol";
import { SwapRouter02 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/SwapRouter02.sol";

contract Quote_AutoCompounderViews_Fuzz_Test is Test {
    function test() public { }
}
