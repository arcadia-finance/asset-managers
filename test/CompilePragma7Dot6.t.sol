/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { CLFactory } from "../lib/accounts-v2/lib/slipstream/contracts/core/CLFactory.sol";
import { CLGauge } from "../lib/accounts-v2/lib/slipstream/contracts/gauge/CLGauge.sol";
import { CLGaugeFactory } from "../lib/accounts-v2/lib/slipstream/contracts/gauge/CLGaugeFactory.sol";
import { CLPoolExtension } from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/CLPoolExtension.sol";
import { CLQuoterV2Extension } from "../lib/accounts-v2/test/utils/extensions/CLQuoterV2Extension.sol";
import { NonfungiblePositionManager } from
    "../lib/accounts-v2/lib/slipstream/contracts/periphery/NonfungiblePositionManager.sol";
import { NonfungiblePositionManagerExtension } from
    "../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/NonfungiblePositionManagerExtension.sol";
import { QuoterV2Extension } from "../lib/accounts-v2/test/utils/extensions/QuoterV2Extension.sol";
import { SwapRouter } from "../lib/accounts-v2/lib/slipstream/contracts/periphery/SwapRouter.sol";
import { SwapRouter02 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/SwapRouter02.sol";
import { Test } from "../lib/accounts-v2/lib/forge-std/src/Test.sol";

contract CompilePragma7Dot6 is Test {
    function test() public { }
}
