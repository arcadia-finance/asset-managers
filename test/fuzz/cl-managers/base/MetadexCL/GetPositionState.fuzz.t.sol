/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "Slipstream", on Metadex CL.
 */
contract GetPositionState_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    using stdStorage for StdStorage;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_MetadexCL(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(metadex03PositionManager), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.poolFee, 0);
        assertEq(position_.tickSpacing, TICK_SPACING);
        // forge-lint: disable-next-item(unsafe-typecast)
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_getPositionState_StakedMetadexCLAM(uint128 liquidityPool, PositionState memory position)
        public
    {
        // Given: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(stakedMetadex03CLAM), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.poolFee, 0);
        assertEq(position_.tickSpacing, TICK_SPACING);
        // forge-lint: disable-next-item(unsafe-typecast)
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 3);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
        assertEq(position_.tokens[2], receiptToken);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_getPositionState_WrappedStakedMetadexCL(
        uint128 liquidityPool,
        PositionState memory position
    ) public {
        // Given: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(wrappedStakedMetadexCL, position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.id, position.id);
        assertEq(position_.poolFee, 0);
        assertEq(position_.tickSpacing, TICK_SPACING);
        // forge-lint: disable-next-item(unsafe-typecast)
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 3);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
        assertEq(position_.tokens[2], receiptToken);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_getPositionState_StakedMetadexCLAM_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        bytes32 salt
    ) public {
        // Given: The ReceiptToken is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(receiptToken);
        (token0, token1) = (address(token0) < address(token1)) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(receiptToken).checked_write(false);

        // And: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(address(stakedMetadex03CLAM), position.id);

        // Then: The reward leg is not added as a third token.
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_getPositionState_WrappedStakedMetadexCL_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        bytes32 salt
    ) public {
        // Given: The ReceiptToken is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(receiptToken);
        (token0, token1) = (address(token0) < address(token1)) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(receiptToken).checked_write(false);

        // And: A valid staked position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        PositionState memory position_ = base.getPositionState(wrappedStakedMetadexCL, position.id);

        // Then: The reward leg is not added as a third token.
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }
}
