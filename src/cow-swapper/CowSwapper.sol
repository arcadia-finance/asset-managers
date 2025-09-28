/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { Borrower } from "../../lib/flash-loan-router/src/mixin/Borrower.sol";
import { ECDSA } from "./libraries/ECDSA.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../guardian/Guardian.sol";
import { GPv2Order } from "../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IERC20 } from "../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { IFlashLoanRouter } from "../../lib/flash-loan-router/src/interface/IFlashLoanRouter.sol";
import { IGPv2Settlement } from "./interfaces/IGPv2Settlement.sol";
import { IOrderHook } from "./interfaces/IOrderHook.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title CoW Swapper for Arcadia Accounts.
 * @author Pragma Labs
 */
contract CowSwapper is IActionBase, Borrower, Guardian {
    using FixedPointMathLib for uint256;
    using GPv2Order for GPv2Order.Data;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The domain separator used for signing orders.
    bytes32 public immutable DOMAIN_SEPARATOR;

    // The contract address of the Hooks Trampoline.
    address public immutable HOOKS_TRAMPOLINE;

    // The EIP-1271 magic value.
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // Mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // Mapping that sets the approved initiator per owner per account.
    mapping(address owner => mapping(address account => address initiator)) public ownerToAccountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The maximum fee charged on the amountOut by the initiator, with 18 decimals precision.
        uint64 maxSwapFee;
        // The contract address of the order hook.
        address orderHook;
    }

    /* //////////////////////////////////////////////////////////////
                          TRANSIENT STORAGE
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Account.
    address internal transient account;

    // The address of the initiator.
    address internal transient initiator;

    // The fee charged on the amountOut by the initiator, with 18 decimals precision.
    uint64 internal transient swapFee;

    // The contract address of the token to swap from.
    address internal transient tokenIn;

    // The amount of tokenIn to swap.
    uint256 internal transient amountIn;

    // The contract address of the token to swap to.
    address internal transient tokenOut;

    // The amount of tokenOut to swap to.
    uint256 internal transient amountOut;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidHash();
    error InvalidInitiator();
    error InvalidOrder();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyHooksTrampoline();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator);
    event FeePaid(address indexed account, address indexed receiver, address indexed asset, uint256 amount);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @dev Throws if called by any address other than the Hooks Trampoline.
     */
    modifier onlyHooksTrampoline() {
        if (msg.sender != HOOKS_TRAMPOLINE) revert OnlyHooksTrampoline();
        _;
    }

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param flashLoanRouter The contract address of the flash-loan router.
     * @param hooksTrampoline The contract address of the hooks trampoline.
     */
    constructor(address owner_, address arcadiaFactory, address flashLoanRouter, address hooksTrampoline)
        Borrower(IFlashLoanRouter(flashLoanRouter))
        Guardian(owner_)
    {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        DOMAIN_SEPARATOR = IGPv2Settlement(address(settlementContract)).domainSeparator();
        HOOKS_TRAMPOLINE = hooksTrampoline;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator_ The address of the initiator.
     * @param maxSwapFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account_,
        address initiator_,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData_
    ) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        if (maxSwapFee > 1e18) revert InvalidValue();

        ownerToAccountToInitiator[owner][account_] = initiator_;
        accountInfo[account_] = AccountInfo({ maxSwapFee: uint64(maxSwapFee), orderHook: orderHook });
        metaData[account_] = metaData_;

        IOrderHook(orderHook).setHook(account_, hookData);

        emit AccountInfoSet(account_, initiator_);
    }

    /* ///////////////////////////////////////////////////////////////
                            FLASH LOAN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Executes a CoW Swap for an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param tokenIn_ The contract address of the token to swap from.
     * @param amountIn_ The amount of tokenIn to swap.
     * @param callBackData The calldata to be passed back to the flash-loan router.
     * @dev Only one transaction at a time can be included per "flashLoanAndSettle()"
     * @dev The check that the solver passed the correct input parameters is done via the signature validation in "isValidSignature()".
     * Both the order parameters (tokenIn_ and amountIn_) as the account_ are included in the messageHash.
     */
    function triggerFlashLoan(address account_, IERC20 tokenIn_, uint256 amountIn_, bytes calldata callBackData)
        internal
        override
        onlyRouter
    {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the Initiator is non zero, we know account_ is an actual Arcadia Account,
        // and the initiator is set by its current owner.
        // If a malicious solver modifies the account, the initiator signature will no longer be valid.
        address initiator_ = ownerToAccountToInitiator[IAccount(account_).owner()][account_];
        if (initiator_ == address(0)) revert InvalidInitiator();

        // Store transient storage.
        initiator = initiator_;
        tokenIn = address(tokenIn_);
        amountIn = amountIn_;

        // No need to approve vault relayer to transfer tokenIn,
        // since settlement contract will call approve() on the tokenIn in a driver interaction.

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(address(tokenIn_), amountIn_, callBackData);

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
        // Caller should be the Account, provided as input in triggerFlashLoan().
        if (msg.sender != account) revert OnlyAccount();

        // Call callback to flash loan router, this will settle the swap.
        flashLoanCallBack(actionTargetData);
        // After the swap, send the bought tokens back to the account.

        // Cache tokenOut.
        address tokenOut_ = tokenOut;

        // Calculate token amounts to be send to Account and initiator.
        // ToDo: Is check is that balance >= amountOut necessary?
        // Think not since this is enforced by CoW Swap?
        uint256 balance = ERC20(tokenOut_).balanceOf(address(this));
        uint256 fee = balance.mulDivDown(swapFee, 1e18);
        uint256 amount = balance - fee;

        // Send the fee to the initiator.
        if (fee > 0) {
            address initiator_ = initiator;
            ERC20(tokenOut_).safeTransfer(initiator_, fee);
            emit FeePaid(msg.sender, initiator_, tokenOut_, fee);
        }

        // Approve tokenOut to be deposited into the account.
        ERC20(tokenOut_).safeApproveWithRetry(msg.sender, amount);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(tokenOut_, amount);
    }

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the swap to store initiator parameters (since they could not be passed during triggerFlashLoan).
     * @param swapFee_ The fee charged on the amountOut by the initiator, with 18 decimals precision.
     * @param tokenOut_ The contract address of the token to swap to.
     * @param amountOut_ The amount of tokenOut to swap to.
     * @param signature Signature encoded as (bytes32 r, bytes32 s, uint8 v).
     * @dev Only for swapFee_ we need to check that the solver passed the correct value via a signature from the initiator.
     * The check for the other input parameters is done via the signature validation in "isValidSignature()".
     * Both tokenOut_ and amountOut_ are part of the order parameters which are included in the messageHash.
     */
    function beforeSwap(uint64 swapFee_, address tokenOut_, uint256 amountOut_, bytes memory signature)
        external
        onlyHooksTrampoline
    {
        // Validate initiator parameters.
        // tokenOut_ and amountOut_ are later validated via the OrderHook.
        if (swapFee > accountInfo[account].maxSwapFee) revert InvalidValue();

        // ToDo: use non replayable signing scheme
        // Validate Signature.
        // ECDSA.recoverSigner() will never return the zero address as signer (reverts instead).
        // Hence if the equality holds, the "initiator" was non-zero, and "account" and "initiator" were verified during "triggerFlashLoan()".
        // No need to check tokenOut_ amountOut_ yet, since those are anyway validated via the signature during "isValidSignature()".
        bytes32 hash_ = keccak256(abi.encode(swapFee_));
        if (ECDSA.recoverSigner(hash_, signature) != initiator) revert InvalidInitiator();

        // Store order related state.
        tokenOut = tokenOut_;
        swapFee = swapFee_;
        amountOut = amountOut_;
    }

    /* ///////////////////////////////////////////////////////////////
                          EIP-1271 LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Verifies according EIP-1271 that the signer is the initiator set for the Arcadia Account.
     * @param orderHash Hash of the CoW Swap order.
     * @param verificationData Encoded data required for verification of the swap.
     * @return magicValue The EIP-1271 magic value.
     */
    function isValidSignature(bytes32 orderHash, bytes calldata verificationData) external view returns (bytes4) {
        // Decode verificationData.
        (GPv2Order.Data memory order, bytes memory signature) = abi.decode(verificationData, (GPv2Order.Data, bytes));

        // Cache Account.
        address account_ = account;

        // Validate order.
        if (
            address(order.sellToken) != tokenIn || order.sellAmount != amountIn || address(order.buyToken) != tokenOut
                || order.buyAmount != amountOut
        ) revert InvalidValue();
        if (orderHash != order.hash(DOMAIN_SEPARATOR)) revert InvalidHash();
        if (!IOrderHook(accountInfo[account_].orderHook).isValidOrder(account_, order)) revert InvalidOrder();

        // Validate Signature.
        // ECDSA.recoverSigner() will never return the zero address as signer (reverts instead).
        // Hence if the equality holds, the "initiator" was non-zero, and "account" and "initiator" were verified during "triggerFlashLoan()".
        bytes32 messageHash = keccak256(abi.encode(orderHash, account_));
        if (ECDSA.recoverSigner(messageHash, signature) != initiator) revert InvalidInitiator();

        // If signature is valid, return EIP-1271 magic value.
        return MAGIC_VALUE;
    }
}
