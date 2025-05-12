/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLGauge } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { SlipstreamExtension } from "../../../utils/extensions/SlipstreamExtension.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { SlipstreamAMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { WrappedStakedSlipstreamFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/WrappedStakedSlipstream.f.sol";

/**
 * @notice Common logic needed by all "Slipstream" fuzz tests.
 */
abstract contract Slipstream_Fuzz_Test is Fuzz_Test, SlipstreamFixture, WrappedStakedSlipstreamFixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    int24 internal constant TICK_SPACING = 1;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint256 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal poolCl;

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
        deployArcadiaAccounts();

        // Deploy fixtures for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
        deployCLGaugeFactory();

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
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        if (staked) {
            // Create gauge.
            vm.prank(address(voter));
            gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(poolCl), address(0), AERO, true));
            voter.setGauge(address(poolCl), address(gauge));
            voter.setAlive(address(gauge), true);
            vm.prank(users.owner);
            stakedSlipstreamAM.addGauge(address(gauge));
        }
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

    function deploySlipstreamAM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        SlipstreamAMExtension slipstreamAM =
            new SlipstreamAMExtension(address(registry), address(slipstreamPositionManager));
        registry.addAssetModule(address(slipstreamAM));
        slipstreamAM.setProtocol();
        vm.stopPrank();
    }

    function deployStakedSlipstreamAM() internal {
        addAssetToArcadia(AERO, 1e18);

        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        stakedSlipstreamAM =
            new StakedSlipstreamAM(address(registry), address(slipstreamPositionManager), address(voter), AERO);
        registry.addAssetModule(address(stakedSlipstreamAM));
        stakedSlipstreamAM.initialize();
        vm.stopPrank();
    }
}
