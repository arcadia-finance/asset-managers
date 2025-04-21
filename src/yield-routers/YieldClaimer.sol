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
import { IPositionManagerV3, CollectParams } from "./interfaces/IPositionManagerV3.sol";
import { IPositionManagerV4 } from "./interfaces/IPositionManagerV4.sol";
import { IStakedSlipstream } from "./interfaces/IStakedSlipstream.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { SafeApprove } from "./libraries/SafeApprove.sol";
import { UniswapV4Logic } from "./libraries/UniswapV4Logic.sol";

/**
 * @title Yield Claimer for concentrated Liquidity Positions.
 * @author Pragma Labs
 */
abstract contract AbstractClaimer is IActionBase {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximum fee an initiator can set, with 18 decimals precision.
    uint256 public immutable MAX_INITIATOR_FEE;

    // The address of reward token (AERO).
    address internal constant REWARD_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // The address of the Slipstream Position Manager.
    address internal constant SLIPSTREAM_POSITION_MANAGER = 0x827922686190790b37229fd06084350E74485b72;

    // The address of the Staked Slipstream AM.
    address internal constant STAKED_SLIPSTREAM_AM = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;

    // The Wrapped Staked Slipstream Asset Module contract.
    address internal constant STAKED_SLIPSTREAM_WRAPPER = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;

    // The address of the Uniswap V3 Position Manager.
    address internal constant UNISWAP_V3_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    // The address of the Uniswap V4 Position Manager.
    address internal constant UNISWAP_V4_POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;

    // The contract address of WETH.
    address internal immutable WETH = 0x4200000000000000000000000000000000000006;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim AERO emissions for, used as transient storage.
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
                // If a fee recipient has not been set, send the fees back to the Account.
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

    function _executeAction(address positionManager, uint256 id)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        if (positionManager == STAKED_SLIPSTREAM_AM || positionManager == STAKED_SLIPSTREAM_WRAPPER) {
            // Case for staked Slipstream positions.
            tokens = new address[](1);
            amounts = new uint256[](1);
            tokens[0] = REWARD_TOKEN;
            amounts[0] = IStakedSlipstream(positionManager).claimReward(id);
        } else if (positionManager == SLIPSTREAM_POSITION_MANAGER || positionManager == UNISWAP_V3_POSITION_MANAGER) {
            // Case for Uniswap V3 and Slipstream positions.
            tokens = new address[](2);
            amounts = new uint256[](2);
            (,, tokens[0], tokens[1],,,,,,,,) = IPositionManagerV3(positionManager).positions(id);
            (amounts[0], amounts[1]) = IPositionManagerV3(positionManager).collect(
                CollectParams({
                    tokenId: id,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        } else if (positionManager == UNISWAP_V4_POSITION_MANAGER) {
            // Case for Uniswap V4 positions.
            tokens = new address[](2);
            amounts = new uint256[](2);
            (PoolKey memory poolKey,) = IPositionManagerV4(UNISWAP_V4_POSITION_MANAGER).getPoolAndPositionInfo(id);
            tokens[0] = Currency.unwrap(poolKey.currency0);
            tokens[1] = Currency.unwrap(poolKey.currency1);
            (amounts[0], amounts[1]) = UniswapV4Logic._collectFees(id, poolKey);

            // If token0 is native ETH, we convert ETH to WETH.
            if (tokens[0] == address(0)) {
                IWETH(payable(WETH)).deposit{ value: amounts[0] }();
                tokens[0] = WETH;
            }
        } else {
            revert InvalidPositionManager();
        }
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
     * @param feeRecipient The address to which the collected fees will be sent.
     * @dev An initiator will be permissioned to compound any
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
}
