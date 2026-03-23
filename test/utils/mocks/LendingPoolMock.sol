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

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    uint96 public minimumMargin;

    address public riskManager;
    address public numeraire;
    address public liquidator;
    address internal callbackAccount;

    ERC20 public asset;

    mapping(address => uint256) public debt;
    mapping(uint256 => bool) public isValidVersion;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error OpenPositionNonZero();

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address asset_) {
        asset = ERC20(asset_);
        numeraire = asset_;
        // Set all account versions as valid by default for testing
        isValidVersion[1] = true;
        isValidVersion[2] = true;
        isValidVersion[3] = true;
        isValidVersion[4] = true;
    }

    /* //////////////////////////////////////////////////////////////
                        LENDINGPOOL FUNCTIONS
    ////////////////////////////////////////////////////////////// */

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

    /* //////////////////////////////////////////////////////////////
                        CREDITOR FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function openMarginAccount(uint256) external view returns (bool, address, address, uint256) {
        // Return success with the asset as numeraire so exposure checks work properly.
        return (true, numeraire, liquidator, minimumMargin);
    }

    function closeMarginAccount(address account) external view {
        if (debt[account] != 0) revert OpenPositionNonZero();
    }

    function getOpenPosition(address account) external view returns (uint256) {
        return debt[account];
    }

    function flashActionCallback(bytes calldata) external {
        // No-op for testing
    }

    function startLiquidation(address, uint256) external view returns (uint256) {
        return debt[msg.sender];
    }

    /* //////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function setNumeraire(address numeraire_) external {
        numeraire = numeraire_;
    }

    function setRiskManager(address riskManager_) external {
        riskManager = riskManager_;
    }

    function setLiquidator(address liquidator_) external {
        liquidator = liquidator_;
    }

    function setMinimumMargin(uint96 minimumMargin_) external {
        minimumMargin = minimumMargin_;
    }

    function setValidVersion(uint256 version, bool isValid) external {
        isValidVersion[version] = isValid;
    }

    function setCallbackAccount(address callbackAccount_) external {
        callbackAccount = callbackAccount_;
    }

    function getCallbackAccount() external view returns (address) {
        return callbackAccount;
    }
}
