/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLGauge } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { RebalancerExtension } from "../../../utils/extensions/RebalancerExtension.sol";
import { RegistryMock } from "../../../utils/mocks/RegistryMock.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "Rebalancer" fuzz tests.
 */
abstract contract Rebalancer_Fuzz_Test is Fuzz_Test, UniswapV3Fixture, SlipstreamFixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;
    int24 internal constant TICK_SPACING = 1;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint256 internal constant MAX_INITIATOR_FEE = 0.01 * 1e18;
    uint256 internal constant MAX_SLIPPAGE_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal poolCl;
    IUniswapV3PoolExtension internal poolUniswap;

    StakedSlipstreamAM internal stakedSlipstreamAM;
    ICLGauge internal gauge;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerExtension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, SlipstreamFixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        rebalancer = new RebalancerExtension(MAX_TOLERANCE, MAX_INITIATOR_FEE, MAX_SLIPPAGE_RATIO);

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = address(rebalancer).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite Arcadia contract addresses, stored as constants in Rebalancer.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );

        // Store overwritten bytecode.
        vm.etch(address(rebalancer), bytecode);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function addAssetsToArcadia(uint256 sqrtPriceX96) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPriceX96 ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function deployAndInitUniswapV3(uint160 sqrtPriceX96, uint128 liquidityPool, uint24 poolFee) internal {
        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPriceX96);

        // Create pool.
        poolUniswap = createPoolUniV3(address(token0), address(token1), poolFee, sqrtPriceX96, 300);

        // Create initial position.
        int24 tickSpacing = poolUniswap.tickSpacing();
        addLiquidityUniV3(
            poolUniswap,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }

    function deployAndInitSlipstream(uint160 sqrtPriceX96, uint128 liquidityPool, int24 tickSpacing) internal {
        // Deploy fixture for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPriceX96);

        // Create pool.
        poolCl = createPoolCL(address(token0), address(token1), tickSpacing, sqrtPriceX96, 300);

        // Create initial position.
        addLiquidityCL(
            poolCl,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }

    function deployAndInitStakedSlipstream(uint160 sqrtPriceX96, uint128 liquidityPool, int24 tickSpacing, bool useAero)
        internal
    {
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();
        {
            RegistryMock registry_ = new RegistryMock();
            bytes memory args = abi.encode(address(registry_), address(slipstreamPositionManager), address(voter), AERO);
            vm.prank(users.owner);
            deployCodeTo("StakedSlipstreamAM.sol", args, 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
            stakedSlipstreamAM = StakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
        }

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 18);
        token1 = useAero ? ERC20Mock(AERO) : new ERC20Mock("TokenB", "TOKB", 18);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPriceX96);

        // Create pool.
        poolCl = createPoolCL(address(token0), address(token1), tickSpacing, sqrtPriceX96, 300);

        // Create gauge.
        vm.prank(address(voter));
        gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(poolCl), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);
        vm.prank(users.owner);
        stakedSlipstreamAM.addGauge(address(gauge));

        // Create initial position.
        addLiquidityCL(
            poolCl,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }
}
