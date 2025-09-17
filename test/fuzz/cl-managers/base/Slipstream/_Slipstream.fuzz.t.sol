/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLSwapRouterFixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/CLSwapRouter.f.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPoint128 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { ICLGauge } from "../../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { ICLPoolExtension } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { ICLSwapRouter } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/interfaces/ICLSwapRouter.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { SlipstreamExtension } from "../../../../utils/extensions/SlipstreamExtension.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";
import { SlipstreamAMExtension } from "../../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamFixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { StakedSlipstreamAM } from "../../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { WrappedStakedSlipstreamFixture } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/slipstream/WrappedStakedSlipstream.f.sol";

/**
 * @notice Common logic needed by all "Slipstream" fuzz tests.
 */
abstract contract Slipstream_Fuzz_Test is
    Fuzz_Test,
    SlipstreamFixture,
    WrappedStakedSlipstreamFixture,
    CLSwapRouterFixture
{
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    int24 internal constant TICK_SPACING = 1;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint64 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal poolCl;

    /// forge-lint: disable-next-line(mixed-case-variable)
    StakedSlipstreamAM internal stakedSlipstreamAM;
    ICLGauge internal gauge;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SlipstreamExtension internal base;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, SlipstreamFixture, WrappedStakedSlipstreamFixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts(address(0));

        // Deploy fixtures for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();
        CLSwapRouterFixture.deploySwapRouter(address(cLFactory), address(weth9));

        // Deploy Staked Position Managers.
        deployStakedSlipstreamAM();
        WrappedStakedSlipstreamFixture.setUp();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // Deploy test contract.
        base = new SlipstreamExtension(
            address(slipstreamPositionManager),
            address(cLFactory),
            address(poolImplementation),
            AERO,
            address(stakedSlipstreamAM),
            address(wrappedStakedSlipstream)
        );
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function initSlipstream() internal returns (uint256 id) {
        id = initSlipstream(2 ** 96, type(uint64).max, TICK_SPACING);
    }

    function initSlipstream(uint160 sqrtPrice, uint128 liquidityPool, int24 tickSpacing)
        internal
        returns (uint256 id)
    {
        // Deploy fixtures for Slipstream.
        SlipstreamFixture.setUp();

        // Add assets to Arcadia.
        addAssetsToArcadia(sqrtPrice);

        // Create pool.
        poolCl = createPoolCL(address(token0), address(token1), tickSpacing, sqrtPrice, 300);

        // Create initial position.
        (id,,) = addLiquidityCL(
            poolCl,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }

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
        // Given: Reasonable current price.
        position.sqrtPrice =
            uint160(bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));

        // And: Pool has reasonable liquidity.
        liquidityPool_ =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        position.sqrtPrice = uint160(position.sqrtPrice);
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice));
        position.tickSpacing = TICK_SPACING;
    }

    function setPoolState(uint128 liquidityPool, PositionState memory position, bool staked) internal {
        // Create pool.
        initSlipstream(uint160(position.sqrtPrice), liquidityPool, position.tickSpacing);
        position.pool = address(poolCl);
        position.fee = poolCl.fee();

        if (staked) {
            position.tokens = new address[](3);
            position.tokens[2] = AERO;
            // Create gauge.
            vm.prank(address(voter));
            gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(poolCl), address(0), AERO, true));
            voter.setGauge(address(poolCl), address(gauge));
            voter.setAlive(address(gauge), true);
            vm.prank(users.owner);
            stakedSlipstreamAM.addGauge(address(gauge));
        } else {
            position.tokens = new address[](2);
        }

        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
    }

    function givenValidPositionState(PositionState memory position) internal {
        int24 tickSpacing = position.tickSpacing;
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolCl.liquidity() / 1e3));
    }

    function setPositionState(PositionState memory position) internal {
        (position.id,,) = addLiquidityCL(
            poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(position.id);
    }

    /// forge-lint: disable-next-item(mixed-case-function, mixed-case-variable)
    function deploySlipstreamAM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        SlipstreamAMExtension slipstreamAM =
            new SlipstreamAMExtension(users.owner, address(registry), address(slipstreamPositionManager));
        registry.addAssetModule(address(slipstreamAM));
        slipstreamAM.setProtocol();
        vm.stopPrank();
    }

    /// forge-lint: disable-next-item(mixed-case-function, mixed-case-variable)
    function deployStakedSlipstreamAM() internal {
        addAssetToArcadia(AERO, 1e18);

        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        stakedSlipstreamAM = new StakedSlipstreamAM(
            users.owner, address(registry), address(slipstreamPositionManager), address(voter), AERO
        );
        registry.addAssetModule(address(stakedSlipstreamAM));
        stakedSlipstreamAM.initialize();
        vm.stopPrank();
    }

    function generateFees(uint256 amount0, uint256 amount1) public {
        vm.startPrank(users.liquidityProvider);
        // Swap token0 for token1
        uint256 amountIn;
        if (amount0 > 0) {
            amountIn = amount0 * 1e6 / poolCl.fee();

            deal(address(token0), users.liquidityProvider, amountIn, true);
            token0.approve(address(clSwapRouter), amountIn);
            clSwapRouter.exactInputSingle(
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

        // Swap token1 for token0
        if (amount1 > 0) {
            amountIn = amount1 * 1e6 / poolCl.fee();

            deal(address(token1), users.liquidityProvider, amountIn, true);
            token1.approve(address(clSwapRouter), amountIn);
            clSwapRouter.exactInputSingle(
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

    function getFeeAmounts(uint256 id) internal view returns (uint256 amount0, uint256 amount1) {
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint256 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        ) = slipstreamPositionManager.positions(id);

        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            _getFeeGrowthInside(tickLower, tickUpper);

        // Calculate the total amount of fees by adding the already realized fees (tokensOwed),
        // to the accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in NonfungiblePositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 = FullMath.mulDiv(
                feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed0;
            amount1 = FullMath.mulDiv(
                feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed1;
        }
    }

    function _getFeeGrowthInside(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        (, int24 tickCurrent,,,,) = poolCl.slot0();
        (,,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,,) = poolCl.ticks(tickLower);
        (,,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,,) = poolCl.ticks(tickUpper);

        // Calculate the fee growth inside of the Liquidity Range since the last time the position was updated.
        // feeGrowthInside can overflow (without reverting), as is the case in the Uniswap fee calculations.
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                feeGrowthInside0X128 =
                    poolCl.feeGrowthGlobal0X128() - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    poolCl.feeGrowthGlobal1X128() - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
    }
}
