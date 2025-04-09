/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AerodromeFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/aerodrome/AerodromeFixture.f.sol";
import { CLSwapRouterFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/CLSwapRouter.f.sol";
import { CompounderHelper_Fuzz_Test } from "../CompounderHelper/_CompounderHelper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ICLSwapRouter } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/interfaces/ICLSwapRouter.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { ISwapRouter } from "../../../../src/compounders/slipstream/interfaces/ISwapRouter.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamAMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { SlipstreamCompounderExtension } from "../../../utils/extensions/SlipstreamCompounderExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "SlipstreamCompounderHelper" fuzz tests.
 */
abstract contract SlipstreamCompounderHelper_Fuzz_Test is CompounderHelper_Fuzz_Test, CLSwapRouterFixture {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal usdStablePool;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(CompounderHelper_Fuzz_Test) {
        CompounderHelper_Fuzz_Test.setUp();

        CLSwapRouterFixture.deploySwapRouter(address(cLFactory), address(weth9));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function generateFees(uint256 amount0ToGenerate, uint256 amount1ToGenerate) public {
        vm.startPrank(users.liquidityProvider);
        ICLSwapRouter.ExactInputSingleParams memory exactInputParams;
        // Swap token0 for token1
        if (amount0ToGenerate > 0) {
            uint256 amount0ToSwap = ((amount0ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token0.decimals());

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token0.approve(address(clSwapRouter), amount0ToSwap);

            exactInputParams = ICLSwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                tickSpacing: usdStablePool.tickSpacing(),
                recipient: users.liquidityProvider,
                deadline: block.timestamp,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            clSwapRouter.exactInputSingle(exactInputParams);
        }

        // Swap token1 for token0
        if (amount1ToGenerate > 0) {
            uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token1.decimals());

            deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
            token1.approve(address(clSwapRouter), amount1ToSwap);

            exactInputParams = ICLSwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                tickSpacing: usdStablePool.tickSpacing(),
                recipient: users.liquidityProvider,
                deadline: block.timestamp,
                amountIn: amount1ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            clSwapRouter.exactInputSingle(exactInputParams);
        }

        vm.stopPrank();
    }
}
