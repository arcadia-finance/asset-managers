/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AbstractBase } from "../base/AbstractBase.sol";
import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { PositionState } from "../state/PositionState.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Abstract Yield Claimer for concentrated Liquidity Positions.
 * @author Pragma Labs
 */
abstract contract YieldClaimer is IActionBase, AbstractBase {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_FEE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to rebalance the fees for, used as transient storage.
    address internal account;

    // A mapping from initiator to rebalancing fee.
    mapping(address initiator => InitiatorInfo) public initiatorInfo;

    // A mapping that sets the approved initiator per owner per ccount.
    mapping(address owner => mapping(address account => address initiator)) public accountToInitiator;

    // A mapping that sets a user-defined address as recipient of the fees.
    mapping(address account => address feeRecipient) public accountToRecipient;

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 id;
    }

    // A struct with information for each specific initiator.
    struct InitiatorInfo {
        // A boolean indicating if the initiator has been set.
        bool set;
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 claimFee;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidInitiator();
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

    event AccountInfoSet(address indexed account, address indexed initiator, address feeRecipient);
    event Claimed(address indexed account, address indexed positionManager, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxFee The maximum fee an initiator can set, with 18 decimals precision.
     */
    constructor(address arcadiaFactory, uint256 maxFee) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        MAX_FEE = maxFee;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param feeRecipient The address to which the collected fees will be sent.
     * @dev An initiator will be permissioned to claim fees for any
     * Liquidity Position held in the specified Arcadia Account.
     */
    function setAccountInfo(address account_, address initiator, address feeRecipient) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();
        if (feeRecipient == address(0)) revert InvalidRecipient();

        accountToInitiator[owner][account_] = initiator;
        accountToRecipient[account_] = feeRecipient;

        emit AccountInfoSet(account_, initiator, feeRecipient);
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the fee requested by an initiator on the amount of yield claimed.
     * @param claimFee The fee charged on claimed fees/rewards by the initiator, with 18 decimals precision.
     * @dev An initiator can update its fee but can only decrease it.
     */
    function setInitiatorInfo(uint256 claimFee) external {
        if (account != address(0)) revert Reentered();

        // Cache struct
        InitiatorInfo memory initiatorInfo_ = initiatorInfo[msg.sender];

        // Check if initiator is already set.
        if (initiatorInfo_.set) {
            // If so, the initiator can only decrease the fee.
            if (claimFee > initiatorInfo_.claimFee) revert InvalidValue();
        } else {
            // If not, the fee can not exceed a certain threshold.
            if (claimFee > MAX_FEE) revert InvalidValue();
            initiatorInfo_.set = true;
        }

        initiatorInfo_.claimFee = uint64(claimFee);

        initiatorInfo[msg.sender] = initiatorInfo_;
    }

    /* ///////////////////////////////////////////////////////////////
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims accrued fees/rewards from a Liquidity Position, owned by an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function claim(address account_, InitiatorParams calldata initiatorParams) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

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

        // Decode actionTargetData.
        (address initiator, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, InitiatorParams));
        address positionManager = initiatorParams.positionManager;

        // Get all pool and position related state.
        PositionState memory position = _getPositionState(positionManager, initiatorParams.id);
        uint256[] memory balances = new uint256[](position.tokens.length);
        uint256[] memory fees = new uint256[](balances.length);

        // Claim pending fees/rewards and update balances.
        _claim(balances, fees, positionManager, position, initiatorInfo[initiator].claimFee);

        // If native eth was claimed, wrap it.
        _stake(balances, positionManager, position);

        // Approve the liquidity position and leftovers to be deposited back into the Account.
        // And transfer the initiator fees to the initiator.
        uint256 count =
            _approveAndTransfer(initiator, balances, fees, positionManager, position, accountToRecipient[msg.sender]);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Claimed(msg.sender, positionManager, position.id);
    }

    /* ///////////////////////////////////////////////////////////////
                    APPROVE AND TRANSFER LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Approves the liquidity position and handles the claimed fees/rewards.
     * @param initiator The address of the initiator.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
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

        count = 1;
        for (uint256 i; i < balances.length; i++) {
            // Skip assets with no balance.
            if (balances[i] == 0) continue;

            if (balances[i] > fees[i]) {
                if (recipient == msg.sender) {
                    // If feeRecipient is the Account itself, deposit fees back into the Account
                    balances[i] = balances[i] - fees[i];
                    ERC20(position.tokens[i]).safeApproveWithRetry(msg.sender, balances[i]);
                    count++;
                } else {
                    // Else, send the fees to the fee recipient.
                    ERC20(position.tokens[i]).safeTransfer(recipient, balances[i] - fees[i]);
                    balances[i] = 0;
                }
            } else {
                fees[i] = balances[i];
                balances[i] = 0;
            }

            // Transfer Initiator fees to the initiator.
            if (fees[i] > 0) ERC20(position.tokens[i]).safeTransfer(initiator, fees[i]);
        }
    }
}
