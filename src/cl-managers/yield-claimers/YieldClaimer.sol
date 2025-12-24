/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../base/AbstractBase.sol";
import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Guardian } from "../../guardian/Guardian.sol";
import { IAccount } from "../../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../../interfaces/IArcadiaFactory.sol";
import { PositionState } from "../state/PositionState.sol";
import { SafeApprove } from "../../libraries/SafeApprove.sol";

/**
 * @title Abstract Yield Claimer for concentrated Liquidity Positions.
 * @author Pragma Labs
 */
abstract contract YieldClaimer is IActionBase, AbstractBase, Guardian {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory internal immutable ARCADIA_FACTORY;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim the yield for, used as transient storage.
    address internal account;

    // A mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // A mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account.
    mapping(address accountOwner => mapping(address account => address initiator)) public accountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The address of the recipient of the claimed fees.
        address feeRecipient;
        // The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 maxClaimFee;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 id;
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 claimFee;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidInitiator();
    error InvalidAccountVersion();
    error InvalidPositionManager();
    error InvalidRecipient();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator);
    event Claimed(address indexed account, address indexed positionManager, uint256 id);
    event YieldTransferred(address indexed account, address indexed receiver, address indexed asset, uint256 amount);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     */
    constructor(address owner_, address arcadiaFactory) Guardian(owner_) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setAssetManager()".
     * @param accountOwner The current owner of the Arcadia Account.
     * param status Bool indicating if the Asset Manager is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     * @dev No need to check that the Account version is 3 or greater (versions with cross account reentrancy guard),
     * since version 1 and 2 don't support the onSetAssetManager hook.
     */
    function onSetAssetManager(address accountOwner, bool, bytes calldata data) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (address initiator, address feeRecipient, uint256 maxClaimFee, bytes memory metaData_) =
            abi.decode(data, (address, address, uint256, bytes));
        _setAccountInfo(msg.sender, accountOwner, initiator, feeRecipient, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param feeRecipient The address of the recipient of the claimed fees.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account_,
        address initiator,
        address feeRecipient,
        uint256 maxClaimFee,
        bytes calldata metaData_
    ) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address accountOwner = IAccount(account_).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();
        // Block Account versions without cross account reentrancy guard.
        if (IAccount(account_).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account_, accountOwner, initiator, feeRecipient, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param feeRecipient The address of the recipient of the claimed fees.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function _setAccountInfo(
        address account_,
        address accountOwner,
        address initiator,
        address feeRecipient,
        uint256 maxClaimFee,
        bytes memory metaData_
    ) internal {
        if (feeRecipient == address(0)) revert InvalidRecipient();
        if (maxClaimFee > 1e18) revert InvalidValue();

        accountToInitiator[accountOwner][account_] = initiator;
        // unsafe cast: maxClaimFee <= 1e18 < type(uint64).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        accountInfo[account_] = AccountInfo({ feeRecipient: feeRecipient, maxClaimFee: uint64(maxClaimFee) });
        metaData[account_] = metaData_;

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                             CLAIMING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims accrued fees/rewards from a Liquidity Position, owned by an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function claim(address account_, InitiatorParams calldata initiatorParams) external whenNotPaused {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the initiator is set, account_ is an actual Arcadia Account.
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(
            initiatorParams.positionManager,
            initiatorParams.id,
            address(0),
            address(0),
            0,
            0,
            abi.encode(msg.sender, initiatorParams)
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

        // Cache accountInfo.
        AccountInfo memory accountInfo_ = accountInfo[msg.sender];

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));
        address positionManager = initiatorParams.positionManager;

        // Validate initiatorParams.
        if (initiatorParams.claimFee > accountInfo_.maxClaimFee) revert InvalidValue();

        // Get all pool and position related state.
        PositionState memory position = _getPositionState(positionManager, initiatorParams.id);
        uint256[] memory balances = new uint256[](position.tokens.length);
        uint256[] memory fees = new uint256[](balances.length);

        // Claim pending yields and update balances.
        _claim(balances, fees, positionManager, position, initiatorParams.claimFee);

        // If native eth was claimed, wrap it.
        _stake(balances, positionManager, position);

        // Approve the liquidity position handle the claimed yields and transfer the initiator fees to the initiator.
        uint256 count =
            _approveAndTransfer(initiator, balances, fees, positionManager, position, accountInfo_.feeRecipient);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Claimed(msg.sender, positionManager, position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                    APPROVE AND TRANSFER LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Approves the liquidity position and handles the claimed yields.
     * @param initiator The address of the initiator.
     * @param balances The balances of the underlying tokens held by the YieldClaimer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @param recipient The address to which the collected fees will be sent.
     * @return count The number of assets approved.
     */
    function _approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        address recipient
    ) internal returns (uint256 count) {
        // Approve the Liquidity Position.
        ERC721(positionManager).approve(msg.sender, position.id);

        // Transfer Initiator fees and handle the claimed yields.
        count = 1;
        address token;
        uint256 amount;
        for (uint256 i; i < balances.length; i++) {
            token = position.tokens[i];

            // Handle the claimed yields.
            if (balances[i] > fees[i]) {
                amount = balances[i] - fees[i];
                if (recipient == msg.sender) {
                    // If feeRecipient is the Account itself, deposit yield back into the Account.
                    balances[i] = amount;
                    ERC20(token).safeApproveWithRetry(msg.sender, amount);
                    count++;
                } else {
                    // Else, send the yield to the fee recipient.
                    ERC20(token).safeTransfer(recipient, amount);
                    balances[i] = 0;
                }
            } else {
                amount = 0;
                fees[i] = balances[i];
                balances[i] = 0;
            }

            // Transfer Initiator fees to the initiator.
            if (fees[i] > 0) ERC20(token).safeTransfer(initiator, fees[i]);
            emit FeePaid(msg.sender, initiator, token, fees[i]);

            if (recipient != msg.sender) emit YieldTransferred(msg.sender, recipient, token, amount);
        }
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
