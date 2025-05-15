/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../state/PositionState.sol";

/**
 * @title Abstract base implementation for managing Liquidity Positions.
 */
abstract contract AbstractBase {
    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event YieldClaimed(address indexed account, address indexed asset, uint256 amount);
    event FeePaid(address indexed account, address indexed receiver, address indexed asset, uint256 amount);

    /* ///////////////////////////////////////////////////////////////
                            POSITION VALIDATION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns if a position manager matches the position manager(s) of the rebalancer.
     * @param positionManager The contract address of the position manager to check.
     * @return isPositionManager_ Bool indicating if the position manager matches.
     */
    function isPositionManager(address positionManager) public view virtual returns (bool isPositionManager_);

    /* ///////////////////////////////////////////////////////////////
                              GETTERS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the underlying assets of the pool.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return token0 The contract address of token0.
     * @return token1 The contract address of token1.
     */
    function _getUnderlyingTokens(address positionManager, uint256 id)
        internal
        view
        virtual
        returns (address token0, address token1);

    /**
     * @notice Returns the position and pool related state.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @return position A struct with position and pool related variables.
     */
    function _getPositionState(address positionManager, uint256 id)
        internal
        view
        virtual
        returns (PositionState memory position);

    /**
     * @notice Returns the liquidity of the Pool.
     * @param position A struct with position and pool related variables.
     * @return liquidity The liquidity of the Pool.
     */
    function _getPoolLiquidity(PositionState memory position) internal view virtual returns (uint128 liquidity);

    /**
     * @notice Returns the sqrtPrice of the Pool.
     * @param position A struct with position and pool related variables.
     * @return sqrtPrice The sqrtPrice of the Pool.
     */
    function _getSqrtPrice(PositionState memory position) internal view virtual returns (uint160 sqrtPrice);

    /* ///////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims fees/rewards from a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @dev Must update the balances after the claim.
     */
    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                          UNSTAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Unstakes a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        virtual;

    /* ///////////////////////////////////////////////////////////////
                             BURN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Burns the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @dev Must update the balances after the burn.
     */
    function _burn(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        virtual;

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @dev Must update the balances and sqrtPrice after the swap.
     */
    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        virtual;

    /* ///////////////////////////////////////////////////////////////
                             MINT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a new Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to mint as liquidity.
     * @param amount1Desired The desired amount of token1 to mint as liquidity.
     * @dev Must update the balances and liquidity and id after the mint.
     */
    function _mint(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                    INCREASE LIQUIDITY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param amount0Desired The desired amount of token0 to add as liquidity.
     * @param amount1Desired The desired amount of token1 to add as liquidity.
     * @dev Must update the balances and delta liquidity after the increase.
     */
    function _increaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal virtual;

    /* ///////////////////////////////////////////////////////////////
                          STAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Unstakes a Liquidity Position.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     */
    function _stake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        virtual;

    /* ///////////////////////////////////////////////////////////////
                      ERC721 HANDLER FUNCTION
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the onERC721Received selector.
     * @dev Required to receive ERC721 tokens via safeTransferFrom.
     */
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
