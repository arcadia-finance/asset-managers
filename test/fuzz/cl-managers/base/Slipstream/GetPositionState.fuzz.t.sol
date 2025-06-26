/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Slipstream_Fuzz_Test } from "./_Slipstream.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "Slipstream".
 */
contract GetPositionState_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Slipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_Slipstream(uint128 liquidityPool, PositionState memory position)
        public
    {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(slipstreamPositionManager), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, poolCl.fee());
        assertEq(position_.tickSpacing, TICK_SPACING);
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }

    function testFuzz_Success_getPositionState_StakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(stakedSlipstreamAM), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, poolCl.fee());
        assertEq(position_.tickSpacing, TICK_SPACING);
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 3);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
        assertEq(position_.tokens[2], AERO);
    }

    function testFuzz_Success_getPositionState_StakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        bytes32 salt
    ) public {
        // Given: Aero is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(stakedSlipstreamAM), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, poolCl.fee());
        assertEq(position_.tickSpacing, TICK_SPACING);
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }

    function testFuzz_Success_getPositionState_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(wrappedStakedSlipstream), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, poolCl.fee());
        assertEq(position_.tickSpacing, TICK_SPACING);
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 3);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
        assertEq(position_.tokens[2], AERO);
    }

    function testFuzz_Success_getPositionState_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        bytes32 salt
    ) public {
        // Given: Aero is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(wrappedStakedSlipstream), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, poolCl.fee());
        assertEq(position_.tickSpacing, TICK_SPACING);
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }
}
