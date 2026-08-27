/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer } from "../../../src/cl-managers/closers/Closer.sol";
import { PositionState } from "../../../src/cl-managers/state/PositionState.sol";

/**
 * @title CloserExtension
 * @notice Extension of Closer contract for testing purposes.
 * @dev Exposes internal functions and implements abstract methods with mock behavior.
 */
contract CloserExtension is Closer {
    /* ///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    /////////////////////////////////////////////////////////////// */

    constructor(address owner_, address arcadiaFactory) Closer(owner_, arcadiaFactory) { }

    /* ///////////////////////////////////////////////////////////////
                    ABSTRACT FUNCTION IMPLEMENTATIONS
    /////////////////////////////////////////////////////////////// */

    function isPositionManager(address) public view override returns (bool) {
        return returnValueBool;
    }

    function _getUnderlyingTokens(address positionManager, uint256 id)
        internal
        view
        override
        returns (address token0, address token1)
    { }

    function _getPositionState(address positionManager, uint256 id)
        internal
        view
        override
        returns (PositionState memory)
    { }

    function _getPoolLiquidity(PositionState memory position) internal view override returns (uint128) { }

    function _getSqrtPrice(PositionState memory position) internal view override returns (uint160) { }

    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) internal override { }

    function _unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    function _burn(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    function _decreaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint128 liquidity
    ) internal override { }

    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        override
    { }

    function _mint(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal override { }

    function _increaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal override { }

    function _stake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    /* ///////////////////////////////////////////////////////////////
                        EXPOSED INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    function getIndex(address[] memory tokens, address token) external pure returns (address[] memory, uint256) {
        return _getIndex(tokens, token);
    }

    function repayDebt(
        uint256[] memory balances,
        uint256[] memory fees,
        address numeraire,
        uint256 index,
        uint256 maxRepayAmount
    ) external returns (uint256[] memory) {
        _repayDebt(balances, fees, numeraire, index, maxRepayAmount);
        return balances;
    }

    function min3(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return _min3(a, b, c);
    }

    function approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position
    ) external returns (uint256, uint256[] memory) {
        uint256 count = _approveAndTransfer(initiator, balances, fees, positionManager, position);
        return (count, balances);
    }

    /* ///////////////////////////////////////////////////////////////
                        EXTENSIONS FOR TESTING
    /////////////////////////////////////////////////////////////// */

    bool internal returnValueBool;

    function setReturnValue(bool returnValue) external {
        returnValueBool = returnValue;
    }

    function getAccount() external view returns (address) {
        return account;
    }

    function setAccount(address account_) external {
        account = account_;
    }
}
