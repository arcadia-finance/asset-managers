/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IStakedSlipstream } from "./interfaces/IStakedSlipstream.sol";
import { SafeApprove } from "../rebalancers/libraries/SafeApprove.sol";

/**
 * @title Claimer for AERO emissions from Staked Slipstream Liquidity Positions.
 * @author Pragma Labs
 */
contract AeroClaimer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The address of the Staked Slipstream AM.
    address internal constant STAKED_SLIPSTREAM_AM = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;

    // The Wrapped Staked Slipstream Asset Module contract.
    address internal constant STAKED_SLIPSTREAM_WRAPPER = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;

    // The address of reward token (AERO).
    address internal constant REWARD_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim AERO emissions for, used as transient storage.
    address internal account;

    // A mapping that sets the approved initiator per account.
    mapping(address account => address initiator) public accountToInitiator;

    // A mapping from initiator to the initiator fee.
    mapping(address initiator => uint256 initiatorFee) public initiatorFee;

    // A mapping from an initiator to a boolean indicating that initiator already has been set.
    mapping(address initiator => bool set) public initiatorSet;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidInitiator();
    error InvalidPositionManager();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AeroClaimed(address indexed account, address indexed positionManager, uint256 id);
    event InitiatorSet(address indexed account, address indexed initiator);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param maxInitiatorFee The maximum initiator fee an initiator can set, with 18 decimals precision.
     */
    constructor(uint256 maxInitiatorFee) {
        MAX_INITIATOR_FEE = maxInitiatorFee;
    }

    /* ///////////////////////////////////////////////////////////////
                             COMPOUNDING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims the pending AERO emissions earned by a Staked Slipstream Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     */
    function claimAero(address account_, address positionManager, uint256 id) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InvalidInitiator();
        if (positionManager != STAKED_SLIPSTREAM_AM && positionManager != STAKED_SLIPSTREAM_WRAPPER) {
            revert InvalidPositionManager();
        }

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(positionManager, id, msg.sender);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit AeroClaimed(account_, positionManager, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param claimData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the deposit data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Collects the fees earned by the position.
     * - Transfers a reward to the initiator.
     */
    function executeAction(bytes calldata claimData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in claimAero().
        if (msg.sender != account) revert OnlyAccount();

        // Decode claimData.
        (address positionManager, uint256 id, address initiator) = abi.decode(claimData, (address, uint256, address));

        // Collect AERO.
        uint256 reward = IStakedSlipstream(positionManager).claimReward(id);

        // Subtract initiator fee, these will be send to the initiator.
        uint256 fee = reward.mulDivDown(initiatorFee[initiator], 1e18);
        reward = reward - fee;

        // Initiator rewards are transferred to the initiator.
        if (fee > 0) ERC20(REWARD_TOKEN).safeTransfer(initiator, fee);

        // Approve Account to deposit Liquidity Position back into the Account.
        IStakedSlipstream(positionManager).approve(msg.sender, id);
        // Approve Account to deposit rewards to the Account.
        if (reward > 0) ERC20(REWARD_TOKEN).safeApproveWithRetry(msg.sender, reward);

        depositData = ArcadiaLogic._encodeDeposit(positionManager, id, REWARD_TOKEN, reward);
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the information requested for an initiator.
     * @param initiatorFee_ The fee paid to the initiator, with 18 decimals precision.
     * @dev An initiator can update its fee but can only decrease it.
     */
    function setInitiatorFee(uint256 initiatorFee_) external {
        if (account != address(0)) revert Reentered();

        // Check if initiator is already set.
        if (initiatorSet[msg.sender]) {
            // If so, the initiator can only decrease the fee.
            if (initiatorFee_ > initiatorFee[msg.sender]) revert InvalidValue();
        } else {
            // If not, the fee can not exceed certain thresholds.
            if (initiatorFee_ > MAX_INITIATOR_FEE) revert InvalidValue();
            initiatorSet[msg.sender] = true;
        }

        initiatorFee[msg.sender] = initiatorFee_;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets an initiator for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @dev An initiator will be permissioned to compound any
     * Liquidity Position held in the specified Arcadia Account.
     * @dev When an Account is transferred to a new owner,
     * the asset manager itself (this contract) and hence its initiator will no longer be allowed by the Account.
     */
    function setInitiator(address account_, address initiator) external {
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        if (msg.sender != IAccount(account_).owner()) revert OnlyAccountOwner();

        accountToInitiator[account_] = initiator;

        emit InitiatorSet(account_, initiator);
    }

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
