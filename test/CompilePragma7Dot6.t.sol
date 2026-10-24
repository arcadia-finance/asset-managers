/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

// forge-lint: disable-start(unused-import)
import { CLFactory } from "../lib/accounts-v2/lib/slipstream/contracts/core/CLFactory.sol";
import { CLGauge } from "../lib/accounts-v2/lib/slipstream/contracts/gauge/CLGauge.sol";
import { CLGaugeFactory } from "../lib/accounts-v2/lib/slipstream/contracts/gauge/CLGaugeFactory.sol";
import { CLPoolExtension } from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/CLPoolExtension.sol";
import { CLQuoterV2Extension } from "../lib/accounts-v2/test/utils/extensions/CLQuoterV2Extension.sol";
import {
    Metadex03CLFactoryExtension
} from "../lib/accounts-v2/test/utils/fixtures/metadex03/extensions/Metadex03CLFactoryExtension.sol";
import {
    Metadex03CLGaugeFactoryExtension
} from "../lib/accounts-v2/test/utils/fixtures/metadex03/extensions/Metadex03CLGaugeFactoryExtension.sol";
import {
    Metadex03CLPoolExtension
} from "../lib/accounts-v2/test/utils/fixtures/metadex03/extensions/Metadex03CLPoolExtension.sol";
import {
    Metadex03CLQuoterV2Extension
} from "../lib/accounts-v2/test/utils/extensions/Metadex03CLQuoterV2Extension.sol";
import {
    Metadex03CLSwapRouterExtension
} from "../lib/accounts-v2/test/utils/fixtures/metadex03/extensions/Metadex03CLSwapRouterExtension.sol";
import {
    Metadex03NonfungiblePositionManagerExtension
} from "../lib/accounts-v2/test/utils/fixtures/metadex03/extensions/Metadex03NonfungiblePositionManagerExtension.sol";
import { MockSwapHook } from "../lib/accounts-v2/test/utils/mocks/Metadex03/MockSwapHook.sol";
import {
    NonfungiblePositionManager
} from "../lib/accounts-v2/lib/slipstream/contracts/periphery/NonfungiblePositionManager.sol";
import {
    NonfungiblePositionManagerExtension
} from "../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/NonfungiblePositionManagerExtension.sol";
import { QuoterV2Extension } from "../lib/accounts-v2/test/utils/extensions/QuoterV2Extension.sol";
import {
    SlipstreamCLFactoryExtension
} from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/SlipstreamCLFactoryExtension.sol";
import {
    SlipstreamCLGaugeExtension
} from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/SlipstreamCLGaugeExtension.sol";
import {
    SlipstreamCLGaugeFactoryExtension
} from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/SlipstreamCLGaugeFactoryExtension.sol";
import {
    SlipstreamCLSwapRouterExtension
} from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/SlipstreamCLSwapRouterExtension.sol";
import {
    SlipstreamNonfungiblePositionManagerExtension
} from "../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/SlipstreamNonfungiblePositionManagerExtension.sol";
import { SwapRouter } from "../lib/accounts-v2/lib/slipstream/contracts/periphery/SwapRouter.sol";
import { SwapRouter02 } from "../lib/accounts-v2/lib/swap-router-contracts/contracts/SwapRouter02.sol";
import { Test } from "../lib/accounts-v2/lib/forge-std-v1.13/src/Test.sol";
// forge-lint: disable-end(unused-import)

contract CompilePragma7Dot6 is Test {
    function test() public { }
}
