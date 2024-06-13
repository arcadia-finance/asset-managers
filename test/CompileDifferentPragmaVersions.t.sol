/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >=0.6.2;
pragma experimental ABIEncoderV2;

import { Test } from "../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { CLFactory } from "../lib/accounts-v2/lib/slipstream/contracts/core/CLFactory.sol";
import { CLPoolExtension } from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/CLPoolExtension.sol";
import { NonfungiblePositionManager } from
    "../lib/accounts-v2/lib/slipstream/contracts/periphery/NonfungiblePositionManager.sol";
import { NonfungiblePositionManagerExtension } from
    "../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/NonfungiblePositionManagerExtension.sol";
import { QuoterV2 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/lens/QuoterV2.sol";
import { SlipstreamQuoterV2Extension } from "./utils/extensions/SlipstreamQuoterV2Extension.sol";
import { SwapRouter } from "../lib/accounts-v2/lib/slipstream/contracts/periphery/SwapRouter.sol";
import { SwapRouter02 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/SwapRouter02.sol";
import { QuoterV2Extension } from "./utils/extensions/QuoterV2Extension.sol";

contract IsCompoundable_SlipstreamAutoCompoundHelper_Fuzz_Test is Test {
    function test() public { }
}
