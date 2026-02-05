/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../guardian/Guardian.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { ILendingPool } from "./interfaces/ILendingPool.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Automatic claimer of Merkl rewards.
 * @author Pragma Labs
 */
contract DebtRepayer is IActionBase, Guardian {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim the yield for.
    address internal transient account;

    // A mapping from account_ to account_ specific information.
    mapping(address account_ => AccountInfo) public accountInfo;

    // A mapping from account_ to custom metadata.
    mapping(address account_ => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account_.
    mapping(address accountOwner => mapping(address account_ => address initiator)) public accountToInitiator;

    // A struct with the account_ specific parameters.
    struct AccountInfo {
        // The maximum fee charged on the amount repaid, with 18 decimals precision.
        uint64 maxFee;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The amount of numeraire withdrawn from the account.
        uint256 amount;
        // The fee charged on the amount repaid, with 18 decimals precision.
        uint256 fee;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidAccountVersion();
    error InvalidInitiator();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account_, address indexed initiator);
    event FeePaid(address indexed account_, address indexed receiver, address indexed asset, uint256 amount);
    event YieldClaimed(address indexed account_, address indexed asset, uint256 amount);
    event YieldTransferred(address indexed account_, address indexed receiver, address indexed asset, uint256 amount);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param factory The contract address of the Arcadia Accounts Factory.
     */
    constructor(address owner_, address factory) Guardian(owner_) {
        ARCADIA_FACTORY = IArcadiaFactory(factory);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setAssetManager()".
     * @param accountOwner The current owner of the Arcadia Account.
     * param status Bool indicating if the Operator is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     * @dev No need to check that the Account version is 3 or greater (versions with cross account_ reentrancy guard),
     * since version 1 and 2 don't support the onSetAssetManager hook.
     */
    function onSetAssetManager(address accountOwner, bool, bytes calldata data) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (address initiator, uint256 maxFee, bytes memory metaData_) = abi.decode(data, (address, uint256, bytes));
        _setAccountInfo(msg.sender, accountOwner, initiator, maxFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param maxFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account_.
     */
    function setAccountInfo(address account_, address initiator, uint256 maxFee, bytes calldata metaData_) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address accountOwner = IAccount(account_).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();
        // Block Account versions without cross account_ reentrancy guard.
        if (IAccount(account_).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account_, accountOwner, initiator, maxFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param maxFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account_.
     */
    function _setAccountInfo(
        address account_,
        address accountOwner,
        address initiator,
        uint256 maxFee,
        bytes memory metaData_
    ) internal {
        if (maxFee > 1e18) revert InvalidValue();

        accountToInitiator[accountOwner][account_] = initiator;
        // unsafe cast: maxFee <= 1e18 < type(uint64).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        accountInfo[account_] = AccountInfo({ maxFee: uint64(maxFee) });
        metaData[account_] = metaData_;

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                             CLAIMING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Repays debt of an Arcadia Account.
     * @param account_ The contract address of the account_.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function repayDebt(address account_, InitiatorParams calldata initiatorParams) external whenNotPaused {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the initiator is set, account_ is an actual Arcadia Account.
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();

        // Validate initiatorParams.
        // No need to check length arrays, as it is checked in _claim() on Distributor.
        if (initiatorParams.fee > accountInfo[account_].maxFee) revert InvalidValue();

        address numeraire = IAccount(account_).numeraire();

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(
            numeraire, initiatorParams.amount, abi.encode(msg.sender, numeraire, initiatorParams)
        );

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param actionTargetData A bytes object containing the initiator and initiatorParams.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in rebalance().
        if (msg.sender != account) revert OnlyAccount();

        // Decode actionTargetData.
        (address initiator, address numeraire, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, address, InitiatorParams));

        ILendingPool lendingPool = ILendingPool(IAccount(msg.sender).creditor());
        uint256 debt = lendingPool.maxWithdraw(msg.sender);

        uint256 debtWithFee = debt.mulDivDown(1e18 + initiatorParams.fee, 1e18);
        uint256 fee;
        uint256 repayAmount;
        if (debtWithFee < initiatorParams.amount) {
            fee = debtWithFee - fee;
            repayAmount = debt;
            // Deposit remainder back into the Account.
            ERC20(numeraire).safeApproveWithRetry(msg.sender, initiatorParams.amount - debtWithFee);
            depositData = ArcadiaLogic._encodeDeposit(numeraire, initiatorParams.amount - debtWithFee);
        } else {
            fee = initiatorParams.amount.mulDivDown(initiatorParams.fee, 1e18);
            repayAmount = initiatorParams.amount - fee;
        }

        // Repay the debt.
        ERC20(numeraire).safeApproveWithRetry(address(lendingPool), repayAmount);
        lendingPool.repay(repayAmount, msg.sender);

        // Transfer Initiator fees to the initiator.
        if (fee > 0) ERC20(numeraire).safeTransfer(initiator, fee);
        emit FeePaid(msg.sender, initiator, numeraire, fee);
    }

    /* ///////////////////////////////////////////////////////////////
                             SKIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Recovers any native or ERC20 tokens left on the contract.
     * @param token The contract address of the token, or address(0) for native tokens.
     */
    function skim(address token) external onlyOwner whenNotPaused {
        if (account != address(0)) revert Reentered();

        if (token == address(0)) {
            (bool success, bytes memory result) = payable(msg.sender).call{ value: address(this).balance }("");
            require(success, string(result));
        } else {
            ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
}
