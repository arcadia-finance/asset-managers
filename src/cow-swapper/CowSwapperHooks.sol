/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData, IActionBase } from "../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { AppData } from "./libraries/AppData.sol";
import { ArcadiaLogicHooks } from "./libraries/ArcadiaLogicHooks.sol";
import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { GPv2Order, IERC20 } from "../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IGPv2Settlement } from "./interfaces/IGPv2Settlement.sol";
import { IOrderHook } from "./interfaces/IOrderHook.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title CoW Swapper for Arcadia Accounts.
 * @author Pragma Labs
 */
contract CowSwapperHooks is IActionBase, ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using GPv2Order for GPv2Order.Data;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    uint256 internal constant NONE = 0x00;
    uint256 internal constant SIGNED = 0x01;
    uint256 internal constant WITHDRAW_INITIATED = 0x02;
    uint256 internal constant WITHDRAWN = 0x03;
    uint256 internal constant DEPOSIT_INITIATED = 0x04;

    bytes32 public immutable DOMAIN_SEPARATOR;

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The contract address of the Hooks Trampoline.
    address public immutable HOOKS_TRAMPOLINE;

    // The contract address of the Settlement.
    IGPv2Settlement public immutable SETTLEMENT;

    // The contract address of the Vault Relayer.
    address public immutable VAULT_RELAYER;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Mapping from account to order.
    mapping(address account => OrderState) public order;

    // Mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // Mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // Mapping that sets the approved initiator per owner per account.
    mapping(address owner => mapping(address account => address initiator)) public ownerToAccountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 maxSwapFee;
        // The contract address of the order hook.
        address orderHook;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        uint64 swapFee;
        // Order Calldata provided by the initiator.
        bytes hookData;
    }

    struct OrderState {
        address initiator;
        uint64 swapFee;
        uint8 status;
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        bytes orderUid;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidOrder();
    error InvalidStatus();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccountOwner();
    error OnlyHooksTrampoline();
    error OnlyInitiator();

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

    /**
     * @dev Throws if called by any address other than the Initiator.
     */
    modifier onlyInitiator(address account_) {
        if (msg.sender != ownerToAccountToInitiator[IAccount(account_).owner()][account_]) revert OnlyInitiator();
        _;
    }

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     */
    constructor(address arcadiaFactory, address hooksTrampoline, address settlement) {
        ARCADIA_FACTORY = IArcadiaFactory(arcadiaFactory);
        HOOKS_TRAMPOLINE = hooksTrampoline;
        SETTLEMENT = IGPv2Settlement(settlement);
        DOMAIN_SEPARATOR = SETTLEMENT.domainSeparator();
        VAULT_RELAYER = SETTLEMENT.vaultRelayer();
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param maxSwapFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param orderHook The contract address of the order hook.
     * @param hookData Hook specific data stored in the hook.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account_,
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData_
    ) external nonReentrant {
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address owner = IAccount(account_).owner();
        if (msg.sender != owner) revert OnlyAccountOwner();

        if (maxSwapFee > 1e18) revert InvalidValue();

        ownerToAccountToInitiator[owner][account_] = initiator;
        accountInfo[account_] = AccountInfo({ orderHook: orderHook, maxSwapFee: uint64(maxSwapFee) });
        metaData[account_] = metaData_;

        IOrderHook(orderHook).setHook(account_, hookData);

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                         PRESIGNING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice .
     * @param account_ The contract address of the Arcadia Account.
     * @dev No need to explicitly verify that account_ is an actual Arcadia Account.
     * If onlyInitiator() does not revert, we know an initiator was set for account_ during setAccountInfo(),
     * where we already checked that account_ is an actual Arcadia Account.
     */
    function preSign(address account_, InitiatorParams calldata initiatorParams)
        external
        nonReentrant
        onlyInitiator(account_)
    {
        // Status has to be either NONE or SIGNED.
        // If status is SIGNED, we need to cancel the old signature.
        uint256 status = order[account_].status;
        if (status == SIGNED) SETTLEMENT.setPreSignature(order[account_].orderUid, false);
        else if (order[account_].status != NONE) revert InvalidStatus();

        // Cache accountInfo.
        AccountInfo memory accountInfo_ = accountInfo[account_];

        // Validate initiator parameters.
        if (initiatorParams.swapFee > accountInfo_.maxSwapFee) revert InvalidValue();

        // Get order data.
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint32 validTo) =
            IOrderHook(accountInfo_.orderHook).getOrderData(account_, initiatorParams.hookData);

        // Calculate orderUid.
        bytes memory orderUid = abi.encodePacked(
            GPv2Order.Data({
                sellToken: IERC20(tokenIn),
                buyToken: IERC20(tokenOut),
                receiver: address(0),
                sellAmount: amountIn,
                buyAmount: amountOut,
                validTo: validTo,
                appData: keccak256(AppData.getAppDataJSON(address(this), account_)),
                feeAmount: 0,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }).hash(DOMAIN_SEPARATOR),
            address(this),
            validTo
        );

        // Store order related state.
        order[account_] = OrderState({
            initiator: msg.sender,
            swapFee: initiatorParams.swapFee,
            status: uint8(SIGNED),
            tokenIn: tokenIn,
            amountIn: amountIn,
            tokenOut: tokenOut,
            orderUid: orderUid
        });

        // Set the new Signature.
        SETTLEMENT.setPreSignature(orderUid, true);
    }

    /**
     * @notice .
     * @param account_ The contract address of the Arcadia Account.
     * @dev No need to explicitly verify that account_ is an actual Arcadia Account.
     * If onlyInitiator() does not revert, we know an initiator was set for account_ during setAccountInfo(),
     * where we already checked that account_ is an actual Arcadia Account.
     */
    function cancelPreSign(address account_) external nonReentrant onlyInitiator(account_) {
        // Check Status.
        if (order[account_].status != SIGNED) revert InvalidStatus();

        // Remove preSignature.
        SETTLEMENT.setPreSignature(order[account_].orderUid, false);

        // Delete the order.
        delete order[account_];
    }

    /* ///////////////////////////////////////////////////////////////
                        RECONCILIATION LOGIC
    /////////////////////////////////////////////////////////////// */
    /**
     * @notice .
     * @param account_ The contract address of the Arcadia Account.
     * @dev No need to explicitly verify that account_ is an actual Arcadia Account.
     * If onlyInitiator() does not revert, we know an initiator was set for account_ during setAccountInfo(),
     * where we already checked that account_ is an actual Arcadia Account.
     */
    function reconciliate(address account_) external nonReentrant onlyInitiator(account_) {
        // Check if status is WITHDRAWN.
        if (order[account_].status != WITHDRAWN) revert InvalidStatus();

        // Check if order was filled.
        uint256 amount = SETTLEMENT.filledAmount(order[account_].orderUid);
        // If the order was not filled, only the beforeSwap hook was called.
        // In this case we need to redeposit the withdrawn assets and cancel the approval and swap.
        if (amount == 0) {
            // Cache tokenIn and amountIn.
            address tokenIn = order[account_].tokenIn;
            amount = order[account_].amountIn;

            // Cancel the order.
            SETTLEMENT.setPreSignature(order[account_].orderUid, false);

            // Decrease allowance of the Vault Relayer with amountIn.
            uint256 allowance = ERC20(tokenIn).allowance(address(this), VAULT_RELAYER);
            ERC20(tokenIn).safeApproveWithRetry(VAULT_RELAYER, allowance - amount);

            // Deposit the tokens back into the account.
            _deposit(account_, tokenIn, amount);
        }
        // If the order was filled, the swap was succesfull but the afterSwap hook was not successfull.
        // In this case we still need to execute afterSwap.
        else {
            _afterSwap(account_, amount);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                         PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    function beforeSwap(address account_) external onlyHooksTrampoline nonReentrant {
        if (order[account_].status != SIGNED) revert InvalidStatus();

        // Encode data for the flash-action.
        address tokenIn = order[account_].tokenIn;
        uint256 amountIn = order[account_].amountIn;
        bytes memory actionData = ArcadiaLogicHooks._encodeWithdrawal(tokenIn, amountIn);

        // Update status.
        order[account_].status = uint8(WITHDRAW_INITIATED);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Update status.
        order[account_].status = uint8(WITHDRAWN);

        // Increase allowance of the Vault Relayer with amountIn.
        uint256 allowance = ERC20(tokenIn).allowance(address(this), VAULT_RELAYER);
        ERC20(tokenIn).safeApproveWithRetry(VAULT_RELAYER, allowance + amountIn);
    }

    /* ///////////////////////////////////////////////////////////////
                         POST SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    function afterSwap(address account_) external onlyHooksTrampoline nonReentrant {
        if (order[account_].status != WITHDRAWN) revert InvalidStatus();

        uint256 amountOut = SETTLEMENT.filledAmount(order[account_].orderUid);

        _afterSwap(account_, amountOut);
    }

    function _afterSwap(address account_, uint256 amountOut) internal {
        // Calculate token amounts.
        uint256 fee = amountOut.mulDivDown(order[account_].swapFee, 1e18);
        amountOut = amountOut - fee;

        // Cache variables.
        address tokenOut = order[account_].tokenOut;
        address initiator = order[account_].initiator;

        // Send the fee to the initiator.
        if (fee > 0) {
            ERC20(tokenOut).safeTransfer(initiator, fee);
            emit FeePaid(account_, initiator, tokenOut, fee);
        }

        _deposit(account_, tokenOut, amountOut);
    }

    function _deposit(address account_, address token, uint256 amount) internal {
        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogicHooks._encodeDeposit(token, amount);

        // Update status.
        order[account_].status = uint8(DEPOSIT_INITIATED);

        // Call flashAction() with this contract as actionTarget.
        IAccount(account_).flashAction(address(this), actionData);

        // Order is either succusfully executed or succusfully reconcilliated, remove order.
        delete order[account_];
    }

    /* ///////////////////////////////////////////////////////////////
                         FLASH ACTION CALLBACK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param actionTargetData A bytes object containing the initiator and initiatorParams.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev When rebalancing we will burn the current Liquidity Position and mint a new one with a new tokenId.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
        // Status can only be different from NONE if msg.sender is an actual Arcadia Account.
        // Hence no need to separately check that msg.sender is an Arcadia Account.
        uint256 status = order[msg.sender].status;

        // If a withdrawal is initiated, we have to do nothing in the callback.
        // If a deposit is initiated, we need to approve tokenOut to be deposited into the Account.
        // For all other statuses, the function should revert.
        if (status == DEPOSIT_INITIATED) {
            // Cache token and amount.
            (address tokenOut, uint256 amountOut) = abi.decode(actionTargetData, (address, uint256));

            // Encode deposit data for the flash-action.
            depositData = ArcadiaLogicHooks._encodeDepositData(tokenOut, amountOut);

            // Approve tokenOut to be deposited into the account.
            ERC20(tokenOut).safeApproveWithRetry(msg.sender, amountOut);
        } else if (status != WITHDRAW_INITIATED) {
            revert InvalidStatus();
        }
    }
}
