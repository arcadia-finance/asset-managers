/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { ICLGauge } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { INonfungiblePositionManagerExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/INonfungiblePositionManagerExtension.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/uniswap-v3/LiquidityAmounts.sol";
import { MintLogic_Fuzz_Test } from "./_MintLogic.fuzz.t.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RegistryMock } from "../../../utils/mocks/RegistryMock.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { WrappedStakedSlipstreamFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/WrappedStakedSlipstream.f.sol";

/**
 * @notice Fuzz tests for the function "_mint" of contract "MintLogic".
 */
contract Mint_MintLogic_Fuzz_Test is
    MintLogic_Fuzz_Test,
    UniswapV3Fixture,
    SlipstreamFixture,
    WrappedStakedSlipstreamFixture
{
    using stdStorage for StdStorage;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;
    int24 internal constant TICK_SPACING = 1;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp()
        public
        override(MintLogic_Fuzz_Test, UniswapV3Fixture, SlipstreamFixture, WrappedStakedSlipstreamFixture)
    {
        MintLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_mint_UniswapV3(
        Rebalancer.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);
        deal(position.token0, address(mintLogic), balance0, true);
        deal(position.token1, address(mintLogic), balance1, true);

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create pool.
        createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(position.sqrtPriceX96), 300);
        position.fee = POOL_FEE;

        // When: Calling _mint().
        (uint256 id, uint256 liquidity, uint256 balance0_, uint256 balance1_) =
            mintLogic.mint(address(nonfungiblePositionManager), position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(id), address(mintLogic));

        // And: Correct liquidity should be returned.
        {
            (,,,,,,, uint256 liquidity_,,,,) = nonfungiblePositionManager.positions(id);
            assertEq(liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(token0.balanceOf(address(mintLogic)), balance0_);
        assertEq(token1.balanceOf(address(mintLogic)), balance1_);
    }

    function testFuzz_Success_mint_Slipstream(
        Rebalancer.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);
        deal(position.token0, address(mintLogic), balance0, true);
        deal(position.token1, address(mintLogic), balance1, true);

        // Deploy fixtures for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();

        // Create pool.
        createPoolCL(address(token0), address(token1), TICK_SPACING, uint160(position.sqrtPriceX96), 300);
        position.tickSpacing = TICK_SPACING;

        // When: Calling _mint().
        (uint256 id, uint256 liquidity, uint256 balance0_, uint256 balance1_) =
            mintLogic.mint(address(slipstreamPositionManager), position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(id), address(mintLogic));

        // And: Correct liquidity should be returned.
        {
            (,,,,,,, uint256 liquidity_,,,,) = slipstreamPositionManager.positions(id);
            assertEq(liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(token0.balanceOf(address(mintLogic)), balance0_);
        assertEq(token1.balanceOf(address(mintLogic)), balance1_);
    }

    function testFuzz_Success_mint_StakedSlipstream(
        Rebalancer.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given: a valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        {
            ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
            ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
            deal(position.token0, address(mintLogic), balance0, true);
            deal(position.token1, address(mintLogic), balance1, true);
        }

        // Deploy fixtures for Staked Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();
        StakedSlipstreamAM stakedSlipstreamAM;
        {
            RegistryMock registry_ = new RegistryMock();
            bytes memory args = abi.encode(address(registry_), address(slipstreamPositionManager), address(voter), AERO);
            vm.prank(users.owner);
            deployCodeTo("StakedSlipstreamAM.sol", args, 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
            stakedSlipstreamAM = StakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
        }

        // Create pool.
        ICLPoolExtension pool =
            createPoolCL(position.token0, position.token1, TICK_SPACING, uint160(position.sqrtPriceX96), 300);
        position.tickSpacing = TICK_SPACING;

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);
        vm.prank(users.owner);
        stakedSlipstreamAM.addGauge(address(gauge));

        // When: Calling _mint().
        (uint256 id, uint256 liquidity, uint256 balance0_, uint256 balance1_) =
            mintLogic.mint(address(stakedSlipstreamAM), position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(id), address(mintLogic));

        // And: Gauge is owner of the slipstream position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(id), address(gauge));

        // And: Correct liquidity should be returned.
        {
            (,,,,,,, uint256 liquidity_,,,,) = slipstreamPositionManager.positions(id);
            assertEq(liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(ERC20(position.token0).balanceOf(address(mintLogic)), balance0_);
        assertEq(ERC20(position.token1).balanceOf(address(mintLogic)), balance1_);
    }

    function testFuzz_Success_mint_WrappedStakedSlipstream(
        Rebalancer.PositionState memory position,
        uint112 balance0,
        uint112 balance1
    ) public {
        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And: a valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, BOUND_TICK_UPPER));
        position.sqrtPriceX96 = uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER, BOUND_SQRT_PRICE_UPPER));

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPriceX96 <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPriceX96), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPriceX96), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contracts holds balances.
        {
            ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
            ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
            deal(position.token0, address(mintLogic), balance0, true);
            deal(position.token1, address(mintLogic), balance1, true);
        }

        // Deploy fixtures for Staked Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();

        // Create pool.
        ICLPoolExtension pool =
            createPoolCL(position.token0, position.token1, TICK_SPACING, uint160(position.sqrtPriceX96), 300);
        position.tickSpacing = TICK_SPACING;

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);

        // When: Calling _mint().
        (uint256 id, uint256 liquidity, uint256 balance0_, uint256 balance1_) =
            mintLogic.mint(address(wrappedStakedSlipstream), position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(id), address(mintLogic));

        // And: Gauge is owner of the slipstream position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(id), address(gauge));

        // And: Correct liquidity should be returned.
        {
            (,,,,,,, uint256 liquidity_,,,,) = slipstreamPositionManager.positions(id);
            assertEq(liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(ERC20(position.token0).balanceOf(address(mintLogic)), balance0_);
        assertEq(ERC20(position.token1).balanceOf(address(mintLogic)), balance1_);
    }
}
