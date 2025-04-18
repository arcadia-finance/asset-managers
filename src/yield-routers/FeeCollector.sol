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
import { FullMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { IAccount } from "./interfaces/IAccount.sol";
import { IPositionManagerV3, CollectParams } from "./interfaces/IPositionManagerV3.sol";
import { IPositionManagerV4 } from "./interfaces/IPositionManagerV4.sol";
import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";
import { SafeApprove } from "./libraries/SafeApprove.sol";
import { SlipstreamLogic } from "./libraries/SlipstreamLogic.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";
import { UniswapV4Logic } from "./libraries/UniswapV4Logic.sol";

/**
 * @title Fee collector for concentrated liquidity positions.
 * @notice This contract will claim fees accrued by a Liquidity Position held in an Arcadia Account.
 * The fees can be sent to a user-defined address.
 * @author Pragma Labs
 */
contract FeeCollector is ReentrancyGuard, IActionBase {
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

    // The Account to collect fees for, used as transient storage.
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
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyPool();
    error OnlyPositionManager();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address initiator, address feeRecipient);
    event FeesCollected(address indexed account, address indexed positionManager, uint256 id);
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
                             REBALANCING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Collects the fees accrued by a Liquidity Position owned by an Arcadia Account.
     * @param account_ The Arcadia Account owning the position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     */
    function collectFees(address account_, address positionManager, uint256 id) external {
        // If the initiator is set, account_ is an actual Arcadia Account.
        if (account != address(0)) revert Reentered();
        if (accountToInitiator[account_] != msg.sender) revert InvalidInitiator();
        if (
            positionManager != address(UniswapV3Logic.POSITION_MANAGER)
                && positionManager != address(UniswapV4Logic.POSITION_MANAGER)
                && positionManager != address(SlipstreamLogic.POSITION_MANAGER)
        ) {
            revert InvalidPositionManager();
        }

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        account = account_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(positionManager, id, msg.sender);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);

        emit FeesCollected(account_, positionManager, id);
    }

    /**
     * @notice Callback function called by the Arcadia Account during a flashAction.
     * @param collectData A bytes object containing a struct with the assetData of the position and the address of the initiator.
     * @return depositData A struct with the deposit data of the Liquidity Position.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev This function will trigger the following actions:
     * - Collects the fees earned by the position.
     * - Transfers a reward to the initiator.
     * - Send the collected fees (after deducting the initiator fee) to either a user-specified recipient or the Arcadia Account.
     */
    function executeAction(bytes calldata collectData) external override returns (ActionData memory depositData) {
        // Caller should be the Account, provided as input in claimAero().
        if (msg.sender != account) revert OnlyAccount();

        // Decode collectData.
        (address positionManager, uint256 id, address initiator) = abi.decode(collectData, (address, uint256, address));

        // Collect fees.
        uint256 feeAmount0;
        uint256 feeAmount1;
        address token0;
        address token1;

        // Case for Uniswap V4 positions.
        if (positionManager == address(UniswapV4Logic.POSITION_MANAGER)) {
            (PoolKey memory poolKey,) = IPositionManagerV4(positionManager).getPoolAndPositionInfo(id);
            (feeAmount0, feeAmount1) = UniswapV4Logic._collectFees(id, poolKey);
            token0 = Currency.unwrap(poolKey.currency0);
            token1 = Currency.unwrap(poolKey.currency1);
        } else {
            // Case for Uniswap V3 and Slipstream positions.
            (feeAmount0, feeAmount1) = IPositionManagerV3(positionManager).collect(
                CollectParams({
                    tokenId: id,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            (,, token0, token1,,,,,,,,) = IPositionManagerV3(positionManager).positions(id);
        }

        // Subtract initiator fee, these will be send to the initiator.
        uint256 initiatorFeeToken0 = feeAmount0.mulDivDown(initiatorFee[initiator], 1e18);
        uint256 initiatorFeeToken1 = feeAmount1.mulDivDown(initiatorFee[initiator], 1e18);
        feeAmount0 -= initiatorFeeToken0;
        feeAmount1 -= initiatorFeeToken1;

        // Initiator rewards are transferred to the initiator.
        if (initiatorFeeToken0 > 0) ERC20(token0).safeTransfer(initiator, initiatorFeeToken0);
        if (initiatorFeeToken1 > 0) ERC20(token1).safeTransfer(initiator, initiatorFeeToken0);

        // Approve Account to deposit Liquidity Position back into the Account.
        ERC721(positionManager).approve(msg.sender, id);

        // If a fee recipient has not been set, send the fees back to the Account.
        address feeRecipient = accountToFeeRecipient[msg.sender];
        if (feeRecipient == address(0)) {
            // Approve Account to deposit fees to the Account.
            if (feeAmount0 > 0) ERC20(token0).safeApproveWithRetry(msg.sender, feeAmount0);
            if (feeAmount1 > 0) ERC20(token1).safeApproveWithRetry(msg.sender, feeAmount1);
            depositData = ArcadiaLogic._encodeDeposit(positionManager, id, token0, token1, feeAmount0, feeAmount1);
        } else {
            // Send the fees to the fee recipient set by the user.
            depositData = ArcadiaLogic._encodeDeposit(positionManager, id, address(0), 0);
            if (feeAmount0 > 0) ERC20(token0).safeTransfer(feeRecipient, feeAmount0);
            if (feeAmount1 > 0) ERC20(token1).safeTransfer(feeRecipient, feeAmount1);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
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

        accountToInitiator[account_] = initiator;
        if (feeRecipient != account_) accountToFeeRecipient[account_] = feeRecipient;

        emit AccountInfoSet(account_, initiator, feeRecipient);
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
