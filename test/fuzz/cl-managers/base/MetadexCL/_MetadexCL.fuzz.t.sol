/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import {
    FixedPoint96
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../../../lib/accounts-v2/test/fuzz/Fuzz.t.sol";
import {
    ICLPoolExtension
} from "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import {
    ICLSwapRouter
} from "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/interfaces/ICLSwapRouter.sol";
import {
    IMetadex03CLGauge
} from "../../../../../lib/accounts-v2/src/asset-modules/Metadex03/interfaces/IMetadex03CLGauge.sol";
import { Metadex03CLFixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/metadex03/Metadex03CL.f.sol";
import {
    Metadex03CLSwapRouterFixture
} from "../../../../../lib/accounts-v2/test/utils/fixtures/metadex03/Metadex03CLSwapRouter.f.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { SlipstreamAMExtension } from "../../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamExtension } from "../../../../utils/extensions/SlipstreamExtension.sol";
import {
    StakedMetadex03CLAMExtension
} from "../../../../../lib/accounts-v2/test/utils/extensions/StakedMetadex03CLAMExtension.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "MetadexCL" fuzz tests.
 */
abstract contract MetadexCL_Fuzz_Test is Fuzz_Test, Metadex03CLFixture, Metadex03CLSwapRouterFixture {
    using stdStorage for StdStorage;

    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    int24 internal constant TICK_SPACING = 1;
    uint24 internal constant MAX_POOL_FEE = 100_000;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint64 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    // The upper bound on a single staking reward.
    uint256 internal constant MAX_REWARD = 1e24;

    uint160 internal constant BOUND_SQRT_PRICE_UPPER = type(uint120).max;
    // forge-lint: disable-start(mixed-case-variable)
    int24 internal BOUND_TICK_UPPER = TickMath.getTickAtSqrtPrice(BOUND_SQRT_PRICE_UPPER);
    // forge-lint: disable-next-line(function-init-state)
    int24 internal BOUND_TICK_LOWER = -BOUND_TICK_UPPER;
    // forge-lint: disable-next-line(function-init-state)
    uint160 internal BOUND_SQRT_PRICE_LOWER = TickMath.getSqrtPriceAtTick(BOUND_TICK_LOWER);
    // forge-lint: disable-end(mixed-case-variable)

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal poolCl;

    // forge-lint: disable-next-line(mixed-case-variable)
    StakedMetadex03CLAMExtension internal stakedMetadex03CLAM;
    IMetadex03CLGauge internal gauge;

    // Placeholder address of the WrappedStakedMetadexCL.
    // forge-lint: disable-next-line(mixed-case-variable)
    address internal wrappedStakedMetadexCL = address(uint160(uint256(keccak256("WrappedStakedMetadexCL"))));

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SlipstreamExtension internal base;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, Metadex03CLFixture) {
        Fuzz_Test.setUp();
        Metadex03CLFixture.setUp();

        // Deploy fixtures for Metadex CL.
        deployMetadex03Periphery();
        deployMetadex03CL();
        deployMetadex03CLGaugeFactory();
        Metadex03CLSwapRouterFixture.deployMetadex03SwapRouter(address(metadex03CLFactory), address(weth9));

        // Deploy Staked Position Manager.
        deployStakedMetadex03CLAM();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (address(token0) < address(token1)) ? (token0, token1) : (token1, token0);

        // Deploy test contract.
        base = new SlipstreamExtension(
            address(metadex03PositionManager),
            address(metadex03CLFactory),
            metadex03PoolImplementation,
            receiptToken,
            address(stakedMetadex03CLAM),
            wrappedStakedMetadexCL
        );
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // forge-lint: disable-next-item(mixed-case-function)
    function initMetadexCL() internal returns (uint256 id) {
        id = initMetadexCL(2 ** 96, type(uint64).max, TICK_SPACING);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function initMetadexCL(uint160 sqrtPrice, uint128 liquidityPool, int24 tickSpacing) internal returns (uint256 id) {
        // Add assets to Arcadia.
        addAssetsToArcadia(sqrtPrice);

        // Create pool.
        poolCl = createPoolMetadex03CL(address(token0), address(token1), tickSpacing, sqrtPrice, 300);

        // forge-lint: disable-next-item(divide-before-multiply)
        // Create initial position.
        (id,,) = addLiquidityMetadex03CL(
            poolCl,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            // forge-lint: disable-next-item(divide-before-multiply)
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }

    // forge-lint: disable-next-item(unsafe-typecast)
    function addAssetsToArcadia(uint256 sqrtPrice) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPrice ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function givenValidPoolState(uint128 liquidityPool, PositionState memory position)
        internal
        view
        returns (uint128 liquidityPool_)
    {
        // forge-lint: disable-next-item(unsafe-typecast)
        // Given: Reasonable current price.
        position.sqrtPrice =
            uint160(bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));
        // forge-lint: disable-next-item(unsafe-typecast)

        // And: Pool has reasonable liquidity.
        uint128 maxLiquidity = tickSpacingToMaxLiquidityPerTick(TICK_SPACING);
        // forge-lint: disable-next-item(unsafe-typecast)
        liquidityPool_ = uint128(bound(liquidityPool, maxLiquidity / 1000, maxLiquidity / 10));
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice));
        position.tickSpacing = TICK_SPACING;
        position.poolFee = uint24(bound(position.poolFee, 1, MAX_POOL_FEE));
    }

    function setPoolState(uint128 liquidityPool, PositionState memory position, bool staked) internal {
        // Create pool.
        // forge-lint: disable-next-item(unsafe-typecast)
        initMetadexCL(uint160(position.sqrtPrice), liquidityPool, position.tickSpacing);
        position.pool = address(poolCl);
        // forge-lint: disable-next-item(unsafe-typecast)
        stdstore.target(address(metadex03CLFactory))
            .sig("tickSpacingToFee(int24)")
            .with_key(uint256(int256(position.tickSpacing)))
            .checked_write(position.poolFee);

        if (staked) {
            position.tokens = new address[](3);
            position.tokens[2] = receiptToken;
            // Create gauge.
            gauge = createGaugeMetadex03CL(poolCl);
            vm.prank(users.owner);
            stakedMetadex03CLAM.addGauge(address(gauge));
        } else {
            position.tokens = new address[](2);
        }

        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
    }

    function givenValidPositionState(PositionState memory position) internal {
        int24 tickSpacing = position.tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolCl.liquidity() / 1e3));
    }

    // Bounds a valid position state with the current price inside the range.
    function givenValidPositionStateInRange(PositionState memory position) internal {
        int24 tickSpacing = position.tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - tickSpacing));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent + tickSpacing, BOUND_TICK_UPPER));
        // forge-lint: disable-next-item(divide-before-multiply)
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        // forge-lint: disable-next-item(unsafe-typecast)
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolCl.liquidity() / 1e3));
    }

    // Bounds a reward growth delta to the gauge's emission budget.
    function givenValidRewardGrowth(PositionState memory position, uint256 rewardGrowthDeltaX128)
        internal
        pure
        returns (uint256 rewardGrowthDeltaX128_)
    {
        rewardGrowthDeltaX128_ =
            bound(rewardGrowthDeltaX128, 0, FullMath.mulDiv(MAX_REWARD, 1 << 128, position.liquidity));
    }

    function setPositionState(PositionState memory position) internal returns (uint256 amount0, uint256 amount1) {
        (position.id, amount0, amount1) = addLiquidityMetadex03CL(
            poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = metadex03PositionManager.positions(position.id);
    }

    // Deploys the existing SlipstreamAM as the unstaked Metadex CL Asset Module.
    // forge-lint: disable-next-item(mixed-case-function,mixed-case-variable)
    function deployMetadex03CLAM() internal {
        vm.startPrank(users.owner);
        SlipstreamAMExtension metadexCLAM =
            new SlipstreamAMExtension(users.owner, address(registry), address(metadex03PositionManager));
        registry.addAssetModule(address(metadexCLAM));
        metadexCLAM.setProtocol();
        vm.stopPrank();
    }

    // forge-lint: disable-next-item(mixed-case-function,mixed-case-variable)
    function deployStakedMetadex03CLAM() internal {
        addAssetToArcadia(receiptToken, 1e18);

        // Deploy and add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        stakedMetadex03CLAM = new StakedMetadex03CLAMExtension(
            users.owner, address(registry), address(metadex03CLGaugeFactory), receiptToken, users.treasury
        );
        registry.addAssetModule(address(stakedMetadex03CLAM));
        stakedMetadex03CLAM.initialize();
        vm.stopPrank();
    }

    // Stakes the position in the Metadex CL gauge through the StakedMetadex03CLAM.
    // forge-lint: disable-next-item(mixed-case-function)
    function stakeInStakedMetadexCLAM(uint256 id) internal {
        vm.startPrank(users.liquidityProvider);
        metadex03PositionManager.approve(address(stakedMetadex03CLAM), id);
        stakedMetadex03CLAM.mint(id);
        vm.stopPrank();
    }

    function setRewardGrowthGlobalX128(uint256 rewardGrowthGlobalX128) internal {
        stdstore.target(address(poolCl))
            .sig(poolCl.rewardGrowthGlobalX128.selector)
            .checked_write(rewardGrowthGlobalX128);
    }

    // Returns the reward a staked position accrues for a given reward growth delta, zero when out of range.
    function getRewards(
        PositionState memory position,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current
    ) internal pure returns (uint256 rewards) {
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPrice
                && position.sqrtPrice < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewards = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, 1 << 128);
        }
    }

    // Funds the gauge's emission entitlement and moves the pool's reward growth to its new value.
    function accrueRewards(uint256 rewards, uint256 rewardGrowthGlobalX128Current) internal {
        addEmissionsToGaugeMetadex03CL(poolCl, address(gauge), rewards);
        vm.warp(block.timestamp + 1);
        setRewardGrowthGlobalX128(rewardGrowthGlobalX128Current);
    }

    function generateFees(uint256 amount0, uint256 amount1) public {
        vm.startPrank(users.liquidityProvider);
        // Swap token0 for token1.
        uint256 amountIn;
        if (amount0 > 0) {
            amountIn = amount0 * 1e6 / poolCl.fee();

            deal(address(token0), users.liquidityProvider, amountIn, true);
            token0.approve(address(metadex03CLSwapRouter), amountIn);
            metadex03CLSwapRouter.exactInputSingle(
                ICLSwapRouter.ExactInputSingleParams({
                    tokenIn: address(token0),
                    tokenOut: address(token1),
                    tickSpacing: poolCl.tickSpacing(),
                    recipient: users.liquidityProvider,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        // Swap token1 for token0.
        if (amount1 > 0) {
            amountIn = amount1 * 1e6 / poolCl.fee();

            deal(address(token1), users.liquidityProvider, amountIn, true);
            token1.approve(address(metadex03CLSwapRouter), amountIn);
            metadex03CLSwapRouter.exactInputSingle(
                ICLSwapRouter.ExactInputSingleParams({
                    tokenIn: address(token1),
                    tokenOut: address(token0),
                    tickSpacing: poolCl.tickSpacing(),
                    recipient: users.liquidityProvider,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
