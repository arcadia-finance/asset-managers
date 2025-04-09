/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CompounderHelper_Fuzz_Test } from "../CompounderHelper/_CompounderHelper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";

/**
 * @notice Common logic needed by all "UniswapV4CompounderHelperLogic" fuzz tests.
 */
abstract contract UniswapV4CompounderHelper_Fuzz_Test is CompounderHelper_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    PoolKey internal stablePoolKey;
    PoolKey internal nativeEthPoolKey;

    struct FeeGrowth {
        uint256 desiredFee0;
        uint256 desiredFee1;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
    }

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(CompounderHelper_Fuzz_Test) {
        CompounderHelper_Fuzz_Test.setUp();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function setFeeState(FeeGrowth memory feeData, PoolKey memory poolKey, uint128 liquidity)
        public
        returns (FeeGrowth memory feeData_)
    {
        // And : Amount in $ to wei.
        feeData.desiredFee0 = PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(nativeEthPoolKey.toId())
            ? feeData.desiredFee0 * 1e18
            : feeData.desiredFee0 * 10 ** token0.decimals();
        feeData.desiredFee1 = feeData.desiredFee1 * 10 ** token1.decimals();

        // And : Calculate expected feeGrowth difference in order to obtain desired fee
        // (fee * Q128) / liquidity = diff in Q128.
        // As fee amount is calculated based on deducting feeGrowthOutside from feeGrowthGlobal,
        // no need to test with fuzzed feeGrowthOutside values as no risk of potential rounding errors (we're not testing UniV4 contracts).
        uint256 feeGrowthDiff0X128 = feeData.desiredFee0.mulDivDown(FixedPoint128.Q128, liquidity);
        feeData.feeGrowthGlobal0X128 = feeGrowthDiff0X128;

        uint256 feeGrowthDiff1X128 = feeData.desiredFee1.mulDivDown(FixedPoint128.Q128, liquidity);
        feeData.feeGrowthGlobal1X128 = feeGrowthDiff1X128;

        // And : Set state
        poolManager.setFeeGrowthGlobal(poolKey.toId(), feeData.feeGrowthGlobal0X128, feeData.feeGrowthGlobal1X128);

        // And : Mint fee to the pool
        PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(nativeEthPoolKey.toId())
            ? vm.deal(address(poolManager), address(poolManager).balance + feeData.desiredFee0)
            : token0.mint(address(poolManager), feeData.desiredFee0);

        token1.mint(address(poolManager), feeData.desiredFee1);

        feeData_ = feeData;
    }
}
