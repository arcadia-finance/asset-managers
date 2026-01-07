/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { CloserUniswapV3 } from "../../../src/cl-managers/closers/CloserUniswapV3.sol";
import { PositionState } from "../../../src/cl-managers/state/PositionState.sol";

contract CloserUniswapV3Extension is CloserUniswapV3 {
    constructor(address owner_, address arcadiaFactory, address positionManager, address uniswapV3Factory)
        CloserUniswapV3(owner_, arcadiaFactory, positionManager, uniswapV3Factory)
    { }

    function getUnderlyingTokens(address positionManager, uint256 id) external view returns (address, address) {
        return _getUnderlyingTokens(positionManager, id);
    }

    function getPositionState(address positionManager, uint256 id) external view returns (PositionState memory) {
        return _getPositionState(positionManager, id);
    }

    function getPoolLiquidity(PositionState memory position) external view returns (uint128) {
        return _getPoolLiquidity(position);
    }

    function getSqrtPrice(PositionState memory position) external view returns (uint160) {
        return _getSqrtPrice(position);
    }

    function claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) external returns (uint256[] memory balances_, uint256[] memory fees_) {
        _claim(balances, fees, positionManager, position, claimFee);
        balances_ = balances;
        fees_ = fees;
    }

    function unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_)
    {
        _unstake(balances, positionManager, position);
        balances_ = balances;
    }

    function burn(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_)
    {
        _burn(balances, positionManager, position);
        balances_ = balances;
    }

    function decreaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint128 liquidityToDecrease
    ) external returns (uint256[] memory balances_) {
        _decreaseLiquidity(balances, positionManager, position, liquidityToDecrease);
        balances_ = balances;
    }

    function stake(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_)
    {
        _stake(balances, positionManager, position);
        balances_ = balances;
    }

    function repayDebt(
        uint256[] memory balances,
        uint256[] memory fees,
        address numeraire,
        uint256 index,
        uint256 maxRepayAmount
    ) external returns (uint256[] memory balances_) {
        _repayDebt(balances, fees, numeraire, index, maxRepayAmount);
        balances_ = balances;
    }

    function approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position
    ) external returns (uint256 count) {
        count = _approveAndTransfer(initiator, balances, fees, positionManager, position);
    }

    function getIndex(address[] memory tokens, address token) external pure returns (address[] memory, uint256) {
        return _getIndex(tokens, token);
    }

    function min3(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return _min3(a, b, c);
    }

    function setAccount(address account_) external {
        account = account_;
    }
}
