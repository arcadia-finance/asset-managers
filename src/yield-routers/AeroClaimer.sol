/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IFactory } from "../interfaces/IFactory.sol";
import { IPermit2 } from "../../lib/accounts-v2/src/interfaces/IPermit2.sol";
import { IStakedSlipstreamAM } from "./interfaces/IStakedSlipstreamAM.sol";

/**
 * @title Permissioned contract to claim AERO emissions from Staked Slipstream Liquidity Positions.
 * @author Pragma Labs
 */
contract AeroClaimer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    address internal constant FACTORY = 0xDa14Fdd72345c4d2511357214c5B89A919768e59;

    // The address of the Staked Slipstream AM.
    address internal constant STAKED_SLIPSTREAM_AM = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;

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

    error InitiatorNotValid();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AeroClaimed(address indexed account, uint256 id);
    event InitiatorSet(address indexed account, address indexed initiator);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param maxInitiatorFee The maximum initiator share an initiator can set.
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
     * @param id The id of the Liquidity Position.
     */
    function claimAero(address account_, uint256 id) external {
        // Store Account address, used to validate the caller of the executeAction() callback.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InitiatorNotValid();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = _encodeActionData(msg.sender, id);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit AeroClaimed(account_, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param claimData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return assetData A struct with the asset data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Collects the fees earned by the position.
     * - Transfers a reward to the initiator.
     */
    function executeAction(bytes calldata claimData) external override returns (ActionData memory assetData) {
        // Caller should be the Account, provided as input in claimAero().
        if (msg.sender != account) revert OnlyAccount();

        // Decode Data.
        address initiator;
        (assetData, initiator) = abi.decode(claimData, (ActionData, address));
        uint256 id = assetData.assetIds[0];

        // Collect AERO.
        uint256 amountClaimed = IStakedSlipstreamAM(STAKED_SLIPSTREAM_AM).claimReward(id);

        // Subtract initiator reward from fees, these will be send to the initiator.
        uint256 initiatorShare = amountClaimed.mulDivDown(initiatorFee[initiator], 1e18);

        // Send AERO rewards to the Account
        uint256 rewardToDeposit = amountClaimed - initiatorShare;
        assetData.assetAmounts[1] = rewardToDeposit;

        // Initiator rewards are transferred to the initiator.
        if (initiatorShare > 0) ERC20(REWARD_TOKEN).safeTransfer(initiator, initiatorShare);

        // Approve Account to deposit Liquidity Position back into the Account.
        IStakedSlipstreamAM(STAKED_SLIPSTREAM_AM).approve(msg.sender, id);
        // Approve Account to deposit rewards to the Account.
        ERC20(REWARD_TOKEN).approve(msg.sender, rewardToDeposit);
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
        if (initiatorFee_ > MAX_INITIATOR_FEE) revert InvalidValue();

        if (!initiatorSet[msg.sender]) {
            initiatorSet[msg.sender] = true;
        } else {
            // Fee can only decrease.
            if (initiatorFee_ > initiatorFee[msg.sender]) revert InvalidValue();
        }

        initiatorFee[msg.sender] = initiatorFee_;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Encodes the action data for the flash-action.
     * @param initiator The address of the initiator.
     * @param id The id of the Liquidity Position.
     * @return actionData Bytes string with the encoded actionData.
     */
    function _encodeActionData(address initiator, uint256 id) internal pure returns (bytes memory actionData) {
        // Encode the asset that has to be withdrawn from and deposited back into the Account.
        address[] memory assets_ = new address[](1);
        assets_[0] = STAKED_SLIPSTREAM_AM;
        uint256[] memory assetIds_ = new uint256[](1);
        assetIds_[0] = id;
        uint256[] memory assetAmounts_ = new uint256[](1);
        assetAmounts_[0] = 1;
        uint256[] memory assetTypes_ = new uint256[](1);
        assetTypes_[0] = 2;

        ActionData memory assetData =
            ActionData({ assets: assets_, assetIds: assetIds_, assetAmounts: assetAmounts_, assetTypes: assetTypes_ });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Already generate the data for the final deposit
        assets_ = new address[](2);
        assets_[0] = STAKED_SLIPSTREAM_AM;
        assets_[1] = REWARD_TOKEN;
        assetIds_ = new uint256[](2);
        assetIds_[0] = id;
        assetAmounts_ = new uint256[](2);
        assetAmounts_[0] = 1;
        // We will add the final amount later once reward is collected.
        assetTypes_ = new uint256[](2);
        assetTypes_[0] = 2;
        assetTypes_[1] = 1;

        assetData =
            ActionData({ assets: assets_, assetIds: assetIds_, assetAmounts: assetAmounts_, assetTypes: assetTypes_ });

        // Data required by this contract when Account does the executeAction() callback during the flash-action.
        bytes memory claimData = abi.encode(assetData, initiator);

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, claimData);
    }

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
        if (!IFactory(FACTORY).isAccount(account_)) revert NotAnAccount();
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
