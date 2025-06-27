/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "./libraries/ArcadiaLogic.sol";
import { Borrower } from "../../lib/flash-loan-router/src/mixin/Borrower.sol";
import { ECDSA } from "./libraries/ECDSA.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IERC20 } from "../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { IFlashLoanRouter } from "../../lib/flash-loan-router/src/interface/IFlashLoanRouter.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title CoW Swapper for Arcadia Accounts.
 * @author Pragma Labs
 */
contract CowSwapper is IActionBase, Borrower {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The EIP-1271 magic value.
    bytes4 internal MAGIC_VALUE = 0x1626ba7e;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Account, used as transient storage.
    address internal account;

    // Mapping from initiator to account.
    mapping(address initiator => address account) public initiatorToAccount;

    // Mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // Mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account.
    mapping(address owner => mapping(address account => address initiator)) public ownerToAccountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The address of the recipient of the claimed fees.
        address initiator;
        // The contract address of the token to swap to.
        address tokenOut;
        // The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 maxSwapFee;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidAccount();
    error InvalidInitiator();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
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
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param flashLoanRouter The contract address of the flash-loan router.
     */
    constructor(address arcadiaFactory, address flashLoanRouter) Borrower(IFlashLoanRouter(flashLoanRouter)) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param tokenOut The contract address of the token to swap to.
     * @param maxSwapFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account_,
        address initiator,
        address tokenOut,
        uint256 maxSwapFee,
        bytes calldata metaData_
    ) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        if (maxSwapFee > 1e18) revert InvalidValue();

        ownerToAccountToInitiator[owner][account_] = initiator;
        accountInfo[account_] =
            AccountInfo({ initiator: initiator, tokenOut: tokenOut, maxSwapFee: uint64(maxSwapFee) });
        metaData[account_] = metaData_;

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                           INITIATOR LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets per Initiator the next account the swap will be executed for.
     * @param account_ The contract address of the Arcadia Account.
     * @dev The account we are swapping for is not part of the signature, and different accounts can have the same initiator.
     * Therefore the Initator has to set for which Account the next swap will be executed for.
     * Otherwise a malicious solver can modify the account to swap for.
     * @dev Each Initiator can only have one pending swap at a time.
     */
    function setInitiatorToAccount(address account_) external {
        if (account != address(0)) revert Reentered();

        initiatorToAccount[msg.sender] = account_;
    }

    /* ///////////////////////////////////////////////////////////////
                            FLASH LOAN LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Executes a CoW Swap for an Arcadia Account.
     * @param account_ The contract address of the account.
     * @param tokenIn The contract address of the token to swap from.
     * @param amount The amount of tokenIn to swap.
     * @param callBackData The calldata to be passed back to the flash-loan router.
     */
    function triggerFlashLoan(address account_, IERC20 tokenIn, uint256 amount, bytes calldata callBackData)
        internal
        override
        onlyRouter
    {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the Initiator is non zero, we know account_ is an actual Arcadia Account set by its current owner.
        address initiator = ownerToAccountToInitiator[IAccount(account_).owner()][account_];
        if (initiator == address(0)) revert InvalidInitiator();

        // Since the account provided by the solver is not part of the signature,
        // we still have to check that it matches the Account set by the initiator before the swap.
        // This ensures that a malicious solver cannot modify the account to swap for.
        if (initiatorToAccount[initiator] != account_) revert InvalidAccount();

        // No need to approve vault relayer to transfer tokenIn,
        // since settlement contract will call approve() on the tokenIn in a driver interaction.

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(address(tokenIn), amount, callBackData);

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

        // Cache accountInfo.
        AccountInfo memory accountInfo_ = accountInfo[msg.sender];

        // Calculate token amounts.
        uint256 balance = ERC20(accountInfo_.tokenOut).balanceOf(address(this));
        uint256 fee = balance.mulDivDown(accountInfo_.maxSwapFee, 1e18);
        uint256 amountOut = balance - fee;

        // Send the fee to the initiator.
        ERC20(accountInfo_.tokenOut).safeTransfer(accountInfo_.initiator, fee);
        emit FeePaid(msg.sender, accountInfo_.initiator, accountInfo_.tokenOut, fee);

        // Approve tokenOut to be deposited into the account.
        ERC20(accountInfo_.tokenOut).safeApproveWithRetry(msg.sender, amountOut);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(accountInfo_.tokenOut, amountOut);
    }

    /* ///////////////////////////////////////////////////////////////
                          EIP-1271 LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Verifies according EIP-1271 that the signer is the initiator set for the Arcadia Account.
     * @param hash_ Hash of message that was signed.
     * @param signature  Signature encoded as (bytes32 r, bytes32 s, uint8 v).
     * @return magicValue The EIP-1271 magic value.
     */
    function isValidSignature(bytes32 hash_, bytes calldata signature) external view returns (bytes4) {
        // If the initiator is non zero, we know that an account was set (hence triggerFlashLoan() was called)
        // and account is an actual Arcadia Account.
        address initiator = accountInfo[account].initiator;

        // Recover the signer of the hash.
        // ECDSA.recoverSigner() will never return the zero address as signer (reverts instead).
        // Hence if the equality holds, we know that it is the correct initiator who signed the message.
        if (ECDSA.recoverSigner(hash_, signature) != initiator) revert InvalidInitiator();

        // If signature is valid, return EIP-1271 magic value.
        return MAGIC_VALUE;
    }
}
