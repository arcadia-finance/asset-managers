/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { ECDSA } from "../../lib/accounts-v2/lib/solady/src/utils/ECDSA.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../guardian/Guardian.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IFlashLoanRouter } from "../../lib/flash-loan-router/src/interface/IFlashLoanRouter.sol";
import { IGPv2Settlement } from "./interfaces/IGPv2Settlement.sol";
import { IOrderHook } from "./interfaces/IOrderHook.sol";
import { SafeTransferLib } from "../../lib/accounts-v2/lib/solady/src/utils/SafeTransferLib.sol";

/**
 * @title CoW Swapper for Arcadia Accounts.
 * @author Pragma Labs
 */
contract CowSwapper is IActionBase, Guardian {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The EIP-1271 magic value.
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The contract address of the Cow Settlement.
    IGPv2Settlement internal immutable COW_SETTLEMENT;

    // The contract address of the Flashloan Router.
    IFlashLoanRouter internal immutable FLASH_LOAN_ROUTER;

    // The contract address of the Hooks Trampoline.
    address public immutable HOOKS_TRAMPOLINE;

    // The contract address of the vault relayer.
    address public immutable VAULT_RELAYER;

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
    // The address of the Account owner.
    address internal transient accountOwner;
    // The address of the initiator.
    address internal transient initiator;

    // The fee charged on the amountOut by the initiator, with 18 decimals precision.
    uint64 internal transient swapFee;

    // The contract address of the token to swap from (sellToken).
    address internal transient tokenIn;
    // The contract address of the token to swap to (buyToken).
    address internal transient tokenOut;

    // The amount of tokenIn to swap (sellAmount).
    uint256 internal transient amountIn;

    // The order hash.
    bytes32 internal transient orderHash;
    // The message hash.
    bytes32 internal transient messageHash;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidAccountVersion();
    error InvalidInitiator();
    error InvalidOrder();
    error InvalidOrderHash();
    error InvalidSigner();
    error InvalidValue();
    error NotAnAccount();
    error MissingSignatureVerification();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyHooksTrampoline();
    error OnlyFlashLoanRouter();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator);
    event FeePaid(address indexed account, address indexed receiver, address indexed asset, uint256 amount);

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
        Guardian(owner_)
    {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        FLASH_LOAN_ROUTER = IFlashLoanRouter(flashLoanRouter);
        COW_SETTLEMENT = IGPv2Settlement(address(FLASH_LOAN_ROUTER.settlementContract()));
        HOOKS_TRAMPOLINE = hooksTrampoline;
        VAULT_RELAYER = COW_SETTLEMENT.vaultRelayer();

        // ToDo: remove after testing.
        address(0x4200000000000000000000000000000000000006).safeApproveWithRetry(VAULT_RELAYER, type(uint256).max);
        address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913).safeApproveWithRetry(VAULT_RELAYER, type(uint256).max);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setAssetManager()".
     * @param accountOwner_ The current owner of the Arcadia Account.
     * param status Bool indicating if the Asset Manager is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     * @dev No need to check that the Account version is 3 or greater (versions with cross account reentrancy guard),
     * since version 1 and 2 don't support the onSetAssetManager hook.
     */
    function onSetAssetManager(address accountOwner_, bool, bytes calldata data) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (address initiator_, uint256 maxSwapFee, address orderHook, bytes memory hookData, bytes memory metaData_) =
            abi.decode(data, (address, uint256, address, bytes, bytes));
        _setAccountInfo(msg.sender, accountOwner_, initiator_, maxSwapFee, orderHook, hookData, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator_ The address of the initiator.
     * @param maxSwapFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param orderHook The contract address of the order hook.
     * @param hookData Encoded data containing hook specific parameters.
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
        address accountOwner_ = IAccount(account_).owner();
        if (msg.sender != accountOwner_) revert OnlyAccountOwner();
        // Block Account versions without cross account reentrancy guard.
        if (IAccount(account_).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account_, accountOwner_, initiator_, maxSwapFee, orderHook, hookData, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param accountOwner_ The current owner of the Arcadia Account.
     * @param initiator_ The address of the initiator.
     * @param maxSwapFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param orderHook The contract address of the order hook.
     * @param hookData Encoded data containing hook specific parameters.
     * @param metaData_ Custom metadata to be stored with the account.
     * @dev The initiator for a specific owner for a specific account must be set to a non zero address to use the CoW Swapper.
     * Also if the Account owner is the only allowed signer.
     */
    function _setAccountInfo(
        address account_,
        address accountOwner_,
        address initiator_,
        uint256 maxSwapFee,
        address orderHook,
        bytes memory hookData,
        bytes memory metaData_
    ) internal {
        if (maxSwapFee > 1e18) revert InvalidValue();

        ownerToAccountToInitiator[accountOwner_][account_] = initiator_;
        // unsafe cast: maxClaimFee <= 1e18 < type(uint64).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        accountInfo[account_] = AccountInfo({ maxSwapFee: uint64(maxSwapFee), orderHook: orderHook });
        metaData[account_] = metaData_;

        IOrderHook(orderHook).setHook(account_, hookData);

        emit AccountInfoSet(account_, initiator_);
    }

    /* ///////////////////////////////////////////////////////////////
                      COW SWAP BORROWER LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Executes a CoW Swap for an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param tokenIn_ The contract address of the token to swap from.
     * @param amountIn_ The amount of tokenIn to swap.
     * @param callBackData The calldata to be passed back to the flash-loan router.
     * @dev Only one account at a time can be included per "flashLoanAndSettle()"
     * @dev The check that the solver passed the correct input parameters is done via the signature validation in "beforeSwap()".
     * Both the order parameters (tokenIn_ and amountIn_) as the account_ are included in the messageHash.
     * If a malicious solver modifies the input parameters, the initiator signature will no longer be valid.
     */
    function flashLoanAndCallBack(address account_, address tokenIn_, uint256 amountIn_, bytes calldata callBackData)
        external
        whenNotPaused
    {
        // Caller must be the Flashloan Router.
        if (msg.sender != address(FLASH_LOAN_ROUTER)) revert OnlyFlashLoanRouter();

        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        if (amountIn_ == 0) revert InvalidValue();

        // If the Initiator is non zero, we know account_ is an actual Arcadia Account,
        // and the initiator is set by its current owner.
        address accountOwner_ = IAccount(account_).owner();
        address initiator_ = ownerToAccountToInitiator[accountOwner_][account_];
        if (initiator_ == address(0)) revert InvalidInitiator();

        // Store transient storage.
        accountOwner = accountOwner_;
        initiator = initiator_;
        tokenIn = tokenIn_;
        amountIn = amountIn_;

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(tokenIn_, amountIn_, callBackData);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Reset account.
        account = address(0);
    }

    /**
     * @notice Dummy approve function required by the settlement contract. Does nothing.
     * @param token The address of the token to approve (unused).
     * @param target The address to approve as spender (unused).
     * @param amount The amount to approve (unused).
     */
    function approve(address token, address target, uint256 amount) external { }

    /**
     * @notice Returns the address of the CoW Settlement contract.
     * @return cowSettlement The address of the settlement contract.
     */
    function settlementContract() external view returns (address cowSettlement) {
        cowSettlement = address(COW_SETTLEMENT);
    }

    /**
     * @notice Returns the address of the flash loan router.
     * @return flashLoanRouter The address of the flash loan router contract.
     */
    function router() external view returns (address flashLoanRouter) {
        flashLoanRouter = address(FLASH_LOAN_ROUTER);
    }

    /* ///////////////////////////////////////////////////////////////
                            SWAPPING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param callBackData A bytes object containing callBack data.
     * @return depositData A struct with the data to deposit the bought tokens in the account.
     */
    function executeAction(bytes calldata callBackData) external override returns (ActionData memory depositData) {
        // Caller must be the Account, provided as input in triggerFlashLoan().
        if (msg.sender != account) revert OnlyAccount();

        // Approve the vault relayer to transfer tokenIn.
        address tokenIn_ = tokenIn;
        tokenIn_.safeApproveWithRetry(VAULT_RELAYER, amountIn);

        // Callback to flash loan router, this will settle the swap.
        FLASH_LOAN_ROUTER.borrowerCallBack(callBackData);
        // After the swap, send the bought tokens back to the account.

        // Verify that "isValidSignature()" was called.
        // A malicious solver could modify the EIP-1271 signature, skipping the check that the orderHash is correct.
        // If isValidSignature() would be skipped, tokenIn would not be transferred from this contract to the vault relayer,
        // and the approval would still be non-zero.
        if (IERC20(tokenIn_).allowance(address(this), VAULT_RELAYER) > 0) {
            revert MissingSignatureVerification();
        }

        // Calculate token amounts to be send to Account and initiator.
        // No need to check that amount >= order.buyAmount, since this is enforced by CoW Swap.
        address tokenOut_ = tokenOut;
        uint256 amount = IERC20(tokenOut_).balanceOf(address(this));
        uint256 fee = amount.mulDivDown(swapFee, 1e18);
        amount = amount - fee;

        // Send the fee to the initiator.
        if (fee > 0) {
            address initiator_ = initiator;
            tokenOut_.safeTransfer(initiator_, fee);
            emit FeePaid(msg.sender, initiator_, tokenOut_, fee);
        }

        // Approve tokenOut to be deposited into the account.
        tokenOut_.safeApproveWithRetry(msg.sender, amount);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(tokenOut_, amount);
    }

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the swap to store the remaining initiator parameters,
     * (since they could not be passed during triggerFlashLoan).
     * @param initiatorData The encoded remaining initiator parameters.
     * @dev There is no guarantee the solver includes the "beforeSwap()" hook in the settlement.
     * If "beforeSwap()" would not be called during the settlement,
     * then "isValidSignature()" or "executeAction()" (if "isValidSignature()" is also skipped) will revert,
     * since the order hash and tokenOut will not be set.
     * @dev GPv2Settlement ensures that signatures for the same orderHash (and hence messageHash) cannot be replayed.
     * No need to again check for replay attacks here.
     * @dev The swapFee, if non-zero is always paid to the initiator, also if the Account owner is the signer.
     * While suboptimal, "isValidSignature()" is a view only function so we can't check who is the actual signer.
     * The Account owner can always sign with the fee set to 0.
     */
    function beforeSwap(bytes calldata initiatorData) external {
        // Caller must be the Hooks Trampoline.
        if (msg.sender != HOOKS_TRAMPOLINE) revert OnlyHooksTrampoline();

        // Cache variables.
        address account_ = account;

        uint64 swapFee_;
        bytes32 orderHash_;
        (swapFee_, tokenOut, orderHash_) =
            IOrderHook(accountInfo[account_].orderHook).getInitiatorParams(account_, tokenIn, amountIn, initiatorData);

        // Validate swapFee.
        if (swapFee_ > accountInfo[account_].maxSwapFee) revert InvalidValue();

        // Store transient state.
        swapFee = swapFee_;
        orderHash = orderHash_;
        messageHash = keccak256(abi.encode(account_, swapFee_, orderHash_));
    }

    /* ///////////////////////////////////////////////////////////////
                          EIP-1271 LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Verifies EIP-1271 signature.
     * @param orderHash_ Hash of the CoW Swap order.
     * @param signature Initiator signature encoded as (bytes32 r, bytes32 s, uint8 v).
     * @return magicValue The EIP-1271 magic value.
     * @dev There is no guarantee the solver includes a call to "isValidSignature()".
     * A malicious solver could modify the signature, skipping the check that the orderHash is correct.
     * If "isValidSignature()" would be skipped, the transaction will revert during "executeAction()".
     * @dev GPv2Settlement ensures that signatures for the same orderHash (and hence messageHash) cannot be replayed.
     * No need to again check for replay attacks here.
     */
    function isValidSignature(bytes32 orderHash_, bytes calldata signature) external view returns (bytes4) {
        // If we are not in a flash loan, return magic value for the verification of off-chain solvers.
        if (account == address(0)) return MAGIC_VALUE;

        // Validate order hash.
        if (orderHash != orderHash_) revert InvalidOrderHash();

        // Validate Signature.
        // ECDSA.recoverSigner() will never return the zero address as signer (reverts instead).
        // Hence if the equality holds, the "initiator" was non-zero, and "account" and "initiator" were verified during "triggerFlashLoan()".
        address signer = ECDSA.recoverCalldata(messageHash, signature);
        if (signer != initiator && signer != accountOwner) revert InvalidSigner();

        // If order hash is valid, return EIP-1271 magic value.
        return MAGIC_VALUE;
    }
}
