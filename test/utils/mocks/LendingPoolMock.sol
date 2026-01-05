/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ERC20 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ILendingPool } from "../../../src/cl-managers/closers/interfaces/ILendingPool.sol";
import { SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";

/**
 * @notice Mock LendingPool for testing.
 */
contract LendingPoolMock is ILendingPool {
    using SafeTransferLib for ERC20;

    ERC20 public asset;
    mapping(address => uint256) public debt;

    constructor(address asset_) {
        asset = ERC20(asset_);
    }

    function setDebt(address account, uint256 debt_) external {
        debt[account] = debt_;
    }

    function maxWithdraw(address account) external view override returns (uint256) {
        return debt[account];
    }

    function repay(uint256 amount, address account) external override {
        // Transfer tokens from caller.
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Burn debt.
        debt[account] -= amount;
    }

    function openMarginAccount(uint256) external pure returns (bool, address, address, uint256) {
        return (true, address(0), address(0), 0);
    }
}
