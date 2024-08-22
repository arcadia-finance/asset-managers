/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../../../../src/libraries/ArcadiaLogic.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/LiquidityAmounts.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "rebalancePosition" of contract "UniswapV3Rebalancer".
 */
contract RebalancePosition_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    // TODO : delete
    event Logg(uint256);

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(0));
        // Given : account is not address(0)
        rebalancer.setAccount(account_);

        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.Reentered.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_NotAnAccount(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(account));
        // Given : account is not an Arcadia Account
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.NotAnAccount.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_InitiatorNotValid(uint256 tokenId, int24 lowerTick, int24 upperTick)
        public
    {
        // Given : Owner of the account has not set an initiator yet
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.InitiatorNotValid.selector);
        rebalancer.rebalancePosition(address(account), tokenId, lowerTick, upperTick);
    }

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        newLowerTick = int24(bound(newLowerTick, lpVars.tickLower - 20, lpVars.tickLower - 1));
        newUpperTick = int24(bound(newUpperTick, lpVars.tickUpper + 1, lpVars.tickUpper + 20));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(address(account), tokenId, newLowerTick, newUpperTick);

        // Then : It should return the correct values
        (,,,,, int24 tickLower, int24 tickUpper, uint256 liquidity,,,,) =
            nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, newLowerTick);
        assertEq(tickUpper, newUpperTick);

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(liquidity)
        );
        uint256 amount1 = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(liquidity)
        );
        (uint256 usdValuePosition, uint256 usdValueRemaining) =
            getValuesInUsd(amount0, amount1, token0.balanceOf(address(account)), token1.balanceOf(address(account)));

        // Ensure the leftovers represent less than 0,1% of the usd value of the newly minted position.
        assertLt(usdValueRemaining, 0.001 * 1e18 * usdValuePosition / 1e18);
    }
}
