/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { BurnLogic_Fuzz_Test } from "./_BurnLogic.fuzz.t.sol";
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
 * @notice Fuzz tests for the function "_burn" of contract "BurnLogic".
 */
contract Burn_BurnLogic_Fuzz_Test is
    BurnLogic_Fuzz_Test,
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
        override(BurnLogic_Fuzz_Test, UniswapV3Fixture, SlipstreamFixture, WrappedStakedSlipstreamFixture)
    {
        BurnLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_burn_UniswapV3(Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create pool.
        IUniswapV3PoolExtension pool =
            createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(position.sqrtPriceX96), 300);

        // Create position.
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityUniV3(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(nonfungiblePositionManager), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint128(amount0), 1e1);
        assertApproxEqAbs(balance1, uint128(amount1), 1e1);
        assertEq(rewards, 0);

        // And: Correct balances are transferred.
        assertEq(token0.balanceOf(address(burnLogic)), balance0);
        assertEq(token1.balanceOf(address(burnLogic)), balance1);
    }

    function testFuzz_Success_burn_Slipstream(Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
        ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        position.token0 = address(token0);
        position.token1 = address(token1);

        // Deploy fixtures for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();

        // Create pool and position.
        ICLPoolExtension pool =
            createPoolCL(address(token0), address(token1), TICK_SPACING, uint160(position.sqrtPriceX96), 300);
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(slipstreamPositionManager), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint128(amount0), 1e1);
        assertApproxEqAbs(balance1, uint128(amount1), 1e1);
        assertEq(rewards, 0);

        // And: Correct balances are transferred.
        assertEq(token0.balanceOf(address(burnLogic)), balance0);
        assertEq(token1.balanceOf(address(burnLogic)), balance1);
    }

    function testFuzz_Success_burn_StakedSlipstream_RewardTokenNotToken0Or1(
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        Rebalancer.PositionState memory position
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        {
            ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
            ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
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

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);
        vm.prank(users.owner);
        stakedSlipstreamAM.addGauge(address(gauge));

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), id);
        stakedSlipstreamAM.mint(id);
        vm.stopPrank();
        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(stakedSlipstreamAM), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint128(amount0), 1e1);
        assertApproxEqAbs(balance1, uint128(amount1), 1e1);
        uint256 rewardsExpected;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPriceX96
                && position.sqrtPriceX96 < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        assertEq(rewards, rewardsExpected);

        // And: Correct balances are transferred.
        assertEq(ERC20(position.token0).balanceOf(address(burnLogic)), balance0);
        assertEq(ERC20(position.token1).balanceOf(address(burnLogic)), balance1);
        assertEq(ERC20(AERO).balanceOf(address(burnLogic)), rewards);
    }

    function testFuzz_Success_burn_StakedSlipstream_RewardTokenIsToken0Or1(
        bytes32 salt,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        Rebalancer.PositionState memory position
    ) public {
        // Given: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        {
            ERC20Mock token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
            ERC20Mock token1 = ERC20Mock(AERO);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
        }

        // Deploy fixtures for Staked Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();
        StakedSlipstreamAM stakedSlipstreamAM = StakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
        {
            RegistryMock registry_ = new RegistryMock();
            bytes memory args = abi.encode(address(registry_), address(slipstreamPositionManager), address(voter), AERO);
            vm.prank(users.owner);
            deployCodeTo("StakedSlipstreamAM.sol", args, address(stakedSlipstreamAM));
        }

        // Create pool.
        ICLPoolExtension pool =
            createPoolCL(position.token0, position.token1, TICK_SPACING, uint160(position.sqrtPriceX96), 300);

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);
        vm.prank(users.owner);
        stakedSlipstreamAM.addGauge(address(gauge));

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), id);
        stakedSlipstreamAM.mint(id);
        vm.stopPrank();
        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // And: rewards do not overflow balances.
        uint256 rewardsExpected;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPriceX96
                && position.sqrtPriceX96 < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        vm.assume(rewardsExpected < type(uint256).max - (position.token0 == AERO ? amount0 : amount1));

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewardsExpected, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(stakedSlipstreamAM), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint256(uint128(amount0)) + (position.token0 == AERO ? rewardsExpected : 0), 1e1);
        assertApproxEqAbs(balance1, uint256(uint128(amount1)) + (position.token1 == AERO ? rewardsExpected : 0), 1e1);
        assertEq(rewards, 0);

        // And: Correct balances are transferred.
        assertEq(ERC20(position.token0).balanceOf(address(burnLogic)), balance0);
        assertEq(ERC20(position.token1).balanceOf(address(burnLogic)), balance1);
    }

    function testFuzz_Success_burn_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        Rebalancer.PositionState memory position
    ) public {
        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        {
            ERC20Mock token0 = new ERC20Mock("TokenA", "TOKA", 0);
            ERC20Mock token1 = new ERC20Mock("TokenB", "TOKB", 0);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
        }

        // Deploy fixtures for Staked Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();

        // Create pool.
        ICLPoolExtension pool =
            createPoolCL(position.token0, position.token1, TICK_SPACING, uint160(position.sqrtPriceX96), 300);

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );

        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), id);
        wrappedStakedSlipstream.mint(id);
        vm.stopPrank();

        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(wrappedStakedSlipstream), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint128(amount0), 1e1);
        assertApproxEqAbs(balance1, uint128(amount1), 1e1);
        uint256 rewardsExpected;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPriceX96
                && position.sqrtPriceX96 < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        assertEq(rewards, rewardsExpected);

        // And: Correct balances are transferred.
        assertEq(ERC20(position.token0).balanceOf(address(burnLogic)), balance0);
        assertEq(ERC20(position.token1).balanceOf(address(burnLogic)), balance1);
        assertEq(ERC20(AERO).balanceOf(address(burnLogic)), rewards);
    }

    function testFuzz_Success_burn_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
        bytes32 salt,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        Rebalancer.PositionState memory position
    ) public {
        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And: A valid position.
        position.tickLower = int24(bound(position.tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 1, TickMath.MAX_TICK));
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        position.liquidity = uint128(bound(position.liquidity, 1, UniswapHelpers.maxLiquidity(1)));

        // And: Position is owned by the contract.
        // Create tokens.
        {
            ERC20Mock token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
            ERC20Mock token1 = ERC20Mock(AERO);
            (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
            position.token0 = address(token0);
            position.token1 = address(token1);
        }

        // Deploy fixtures for Staked Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();

        // Create pool.
        ICLPoolExtension pool =
            createPoolCL(position.token0, position.token1, TICK_SPACING, uint160(position.sqrtPriceX96), 300);

        // Create gauge.
        vm.prank(address(voter));
        ICLGauge gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(pool), address(0), AERO, true));
        voter.setGauge(address(gauge));
        voter.setAlive(address(gauge), true);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        (uint256 id, uint256 amount0, uint256 amount1) = addLiquidityCL(
            pool, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), id);
        wrappedStakedSlipstream.mint(id);
        vm.stopPrank();
        // Actual liquidity is always a bit less than the specified liquidity.
        (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(burnLogic), id);

        // And: rewards do not overflow balances.
        uint256 rewardsExpected;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPriceX96
                && position.sqrtPriceX96 < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        vm.assume(rewardsExpected < type(uint256).max - (position.token0 == AERO ? amount0 : amount1));

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewardsExpected, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1, uint256 rewards) =
            burnLogic.burn(address(wrappedStakedSlipstream), id, position);

        // Then: Correct balances should be returned.
        // Note: position manager does unsafe cast from uint256 to uint128.
        assertApproxEqAbs(balance0, uint256(uint128(amount0)) + (position.token0 == AERO ? rewardsExpected : 0), 1e1);
        assertApproxEqAbs(balance1, uint256(uint128(amount1)) + (position.token1 == AERO ? rewardsExpected : 0), 1e1);
        assertEq(rewards, 0);

        // And: Correct balances are transferred.
        assertEq(ERC20(position.token0).balanceOf(address(burnLogic)), balance0);
        assertEq(ERC20(position.token1).balanceOf(address(burnLogic)), balance1);
    }
}
