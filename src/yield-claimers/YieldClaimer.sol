/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { Currency } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { ImmutableState } from "./base/ImmutableState.sol";
import { IPositionManagerV3, CollectParams } from "./interfaces/IPositionManagerV3.sol";
import { IPositionManagerV4 } from "./interfaces/IPositionManagerV4.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { StakedSlipstreamLogic } from "./base/StakedSlipstreamLogic.sol";
import { UniswapV3Logic } from "./base/UniswapV3Logic.sol";
import { UniswapV4Logic } from "./base/UniswapV4Logic.sol";

/**
 * @title Yield Claimer for concentrated Liquidity Positions.
 * @author Pragma Labs
 */
contract YieldClaimer is IActionBase, ImmutableState, StakedSlipstreamLogic, UniswapV3Logic, UniswapV4Logic {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim for, used as transient storage.
    address internal account;

    // A mapping that sets the approved initiator per account.
    mapping(address account => address initiator) public accountToInitiator;

    // A mapping that sets a user-defined address as recipient of the fees.
    mapping(address account => address feeRecipient) public accountToFeeRecipient;

    // A mapping from initiator to the initiator fee.
    mapping(address initiator => uint256 initiatorFee) public initiatorFee;

    // A mapping from an initiator to a boolean indicating that initiator already has been set.
    mapping(address initiator => bool set) public initiatorSet;

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

    event AccountInfoSet(address indexed account, address initiator, address feeRecipient);
    event Claimed(address indexed account, address indexed positionManager, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param rewardToken The address of the reward token for staked Slipstream positions (AERO).
     * @param slipstreamPositionManager The address of the Slipstream Position Manager contract.
     * @param stakedSlipstreamAM The address of the Staked Slipstream Asset Manager contract.
     * @param stakedSlipstreamWrapper The address of the wrapper contract for staked Slipstream assets.
     * @param uniswapV3PositionManager The address of the Uniswap V3 Position Manager contract.
     * @param uniswapV4PositionManager The address of the Uniswap V4 Position Manager contract.
     * @param weth The address of the WETH token contract.
     * @param maxInitiatorFee The maximum fee (with 18 decimals precision) that an initiator can set.
     */
    constructor(
        address rewardToken,
        address slipstreamPositionManager,
        address stakedSlipstreamAM,
        address stakedSlipstreamWrapper,
        address uniswapV3PositionManager,
        address uniswapV4PositionManager,
        address weth,
        uint256 maxInitiatorFee
    )
        ImmutableState(
            rewardToken,
            slipstreamPositionManager,
            stakedSlipstreamAM,
            stakedSlipstreamWrapper,
            uniswapV3PositionManager,
            uniswapV4PositionManager,
            weth
        )
    {
        MAX_INITIATOR_FEE = maxInitiatorFee;
    }

    /* ///////////////////////////////////////////////////////////////
                             CLAIMING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims accrued fees from a Liquidity Position associated with an Arcadia Account,
     * and transfers them to the designated fee recipient, as configured by the Account owner.
     * The recipient may be the Account itself.
     * @param account_ The Arcadia Account owning the position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     */
    function claim(address account_, address positionManager, uint256 id) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InvalidInitiator();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(positionManager, id, msg.sender);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit Claimed(account_, positionManager, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param claimData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the deposit data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Collects the fees earned by the position.
     * - Transfers a reward to the initiator.
     * - Transfers the fees to the user-defined fee recipient.
     */
    function executeAction(bytes calldata claimData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in claimAero().
        if (msg.sender != account) revert OnlyAccount();

        // Decode claimData.
        (address positionManager, uint256 id, address initiator) = abi.decode(claimData, (address, uint256, address));

        // Execute action.
        (address[] memory tokens, uint256[] memory amounts) = _executeAction(positionManager, id);

        // Cache fee recipient and Intitator fee.
        address feeRecipient = accountToFeeRecipient[msg.sender];
        uint256 initiatorFee_ = initiatorFee[initiator];

        // Approve Account to deposit Liquidity Position back into the Account.
        ERC721(positionManager).approve(msg.sender, id);

        // Approve or transfer the ERC20 yield tokens.
        uint256 fee;
        uint256 count = 1;
        for (uint256 i; i < amounts.length; i++) {
            // Initiator rewards are transferred to the initiator.
            fee = amounts[i].mulDivDown(initiatorFee_, 1e18);
            if (fee > 0) ERC20(tokens[i]).safeTransfer(initiator, fee);

            amounts[i] -= fee;
            if (amounts[i] > 0) {
                // If feeRecipient is the Account itself, deposit fees back into the Account
                if (feeRecipient == msg.sender) {
                    ERC20(tokens[i]).safeApproveWithRetry(msg.sender, amounts[i]);
                    count++;
                }
                // Else, send the fees to the fee recipient.
                else {
                    ERC20(tokens[i]).safeTransfer(feeRecipient, amounts[i]);
                }
            }
        }

        // Encode the deposit data.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, id, tokens, amounts, count);
    }

    /**
     * @notice Claims fees or rewards from the given Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The ID of the liquidity position.
     * @return tokens The fee/reward tokens.
     * @return amounts The corresponding token amounts.
     */
    function _executeAction(address positionManager, uint256 id)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        if (positionManager == address(STAKED_SLIPSTREAM_AM) || positionManager == address(STAKED_SLIPSTREAM_WRAPPER)) {
            // Case for Staked Slipstream positions.
            (tokens, amounts) = StakedSlipstreamLogic.claimReward(positionManager, id);
        } else if (
            positionManager == address(SLIPSTREAM_POSITION_MANAGER)
                || positionManager == address(UNISWAP_V3_POSITION_MANAGER)
        ) {
            // Case for Uniswap V3 and Slipstream positions.
            (tokens, amounts) = UniswapV3Logic.claimFees(positionManager, id);
        } else if (positionManager == address(UNISWAP_V4_POSITION_MANAGER)) {
            // Case for Uniswap V4 positions.
            (tokens, amounts) = UniswapV4Logic.claimFees(id);
        } else {
            revert InvalidPositionManager();
        }
    }

    /* ///////////////////////////////////////////////////////////////
                            INITIATORS LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the fee requested by an initiator on the amount of yield claimed.
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
     * @param feeRecipient The address to which the collected fees will be sent.
     * @dev An initiator will be permissioned to claim fees for any
     * Liquidity Position held in the specified Arcadia Account.
     * @dev When an Account is transferred to a new owner,
     * the asset manager itself (this contract) and hence its initiator will no longer be allowed by the Account.
     */
    function setAccountInfo(address account_, address initiator, address feeRecipient) external {
        if (account != address(0)) revert Reentered();
        if (!ArcadiaLogic.FACTORY.isAccount(account_)) revert NotAnAccount();
        if (msg.sender != IAccount(account_).owner()) revert OnlyAccountOwner();
        if (feeRecipient == address(0)) revert InvalidRecipient();

        accountToInitiator[account_] = initiator;
        accountToFeeRecipient[account_] = feeRecipient;

        emit AccountInfoSet(account_, initiator, feeRecipient);
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

    /* ///////////////////////////////////////////////////////////////
                      NATIVE ETH HANDLER
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Receives native ether.
     * @dev Required for native ETH fee collected from UniswapV4 pools.
     */
    receive() external payable { }
}
