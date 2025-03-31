/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CompounderHelper_Fuzz_Test } from "../CompounderHelper/_CompounderHelper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { SwapRouter02Fixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/SwapRouter02Fixture.f.sol";
import { UniswapV3Compounder_Fuzz_Test } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";

/**
 * @notice Common logic needed by all "UniswapV3CompounderHelperLogic" fuzz tests.
 */
abstract contract UniswapV3CompounderHelper_Fuzz_Test is CompounderHelper_Fuzz_Test, SwapRouter02Fixture {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    IUniswapV3PoolExtension internal usdStablePool;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(CompounderHelper_Fuzz_Test) {
        CompounderHelper_Fuzz_Test.setUp();

        SwapRouter02Fixture.deploySwapRouter02(
            address(0), address(uniswapV3Factory), address(nonfungiblePositionManager), address(weth9)
        );
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function generateFees(uint256 amount0ToGenerate, uint256 amount1ToGenerate) public {
        vm.startPrank(users.liquidityProvider);
        ISwapRouter02.ExactInputSingleParams memory exactInputParams;
        // Swap token0 for token1
        if (amount0ToGenerate > 0) {
            uint256 amount0ToSwap = ((amount0ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token0.decimals());

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            token0.approve(address(swapRouter), amount0ToSwap);

            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: usdStablePool.fee(),
                recipient: users.liquidityProvider,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
        }

        // Swap token1 for token0
        if (amount1ToGenerate > 0) {
            uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token1.decimals());

            deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
            token1.approve(address(swapRouter), amount1ToSwap);

            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: usdStablePool.fee(),
                recipient: users.liquidityProvider,
                amountIn: amount1ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
        }

        vm.stopPrank();
    }
}
