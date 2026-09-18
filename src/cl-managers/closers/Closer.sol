/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { AbstractBase } from "../base/AbstractBase.sol";
import { ActionData, IActionBase } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC721 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../../guardian/Guardian.sol";
import { IAccount } from "../../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../../interfaces/IArcadiaFactory.sol";
import { ILendingPool } from "./interfaces/ILendingPool.sol";
import { PositionState } from "../state/PositionState.sol";
import { SafeApprove } from "../../libraries/SafeApprove.sol";

/**
 * @title Abstract Closer of Concentrated Liquidity Positions.
 * @author Pragma Labs
 */
abstract contract Closer is IActionBase, AbstractBase, Guardian {
    using FixedPointMathLib for uint256;
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from account_ to account_ specific information.
    mapping(address account_ => AccountInfo) public accountInfo;

    // A mapping from account_ to custom metadata.
    mapping(address account_ => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account_.
    mapping(address accountOwner => mapping(address account_ => address initiator)) public accountToInitiator;

    // A struct with the account_ specific parameters.
    struct AccountInfo {
        // The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint64 maxClaimFee;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The contract address of the position manager.
        address positionManager;
        // The id of the position.
        uint96 id;
        // The amount of numeraire withdrawn from the account.
        uint256 withdrawAmount;
        // The maximum amount of numeraire to be repaid.
        uint256 maxRepayAmount;
        // The fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
        uint256 claimFee;
        // The maximum amount of liquidity to decrease.
        uint128 liquidity;
    }

    /* //////////////////////////////////////////////////////////////
                          TRANSIENT STORAGE
    ////////////////////////////////////////////////////////////// */

    // The Account to claim the yield for.
    address internal transient account;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidAccountVersion();
    error InvalidInitiator();
    error InvalidNumeraire();
    error InvalidPositionManager();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error Reentered();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account_, address indexed initiator);
    event Close(address indexed account, address indexed positionManager, uint256 id);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param factory The contract address of the Arcadia Accounts Factory.
     */
    constructor(address owner_, address factory) Guardian(owner_) {
        ARCADIA_FACTORY = IArcadiaFactory(factory);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setAssetManager()".
     * @param accountOwner The current owner of the Arcadia Account.
     * param status Bool indicating if the Operator is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     * @dev No need to check that the Account version is 3 or greater (versions with cross account_ reentrancy guard),
     * since version 1 and 2 don't support the onSetAssetManager hook.
     */
    function onSetAssetManager(address accountOwner, bool, bytes calldata data) external {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (address initiator, uint256 maxClaimFee, bytes memory metaData_) = abi.decode(data, (address, uint256, bytes));
        _setAccountInfo(msg.sender, accountOwner, initiator, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account_.
     */
    function setAccountInfo(address account_, address initiator, uint256 maxClaimFee, bytes calldata metaData_)
        external
    {
        if (account != address(0)) revert Reentered();
        if (!ARCADIA_FACTORY.isAccount(account_)) revert NotAnAccount();
        address accountOwner = IAccount(account_).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();
        // Block Account versions without cross account_ reentrancy guard.
        if (IAccount(account_).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account_, accountOwner, initiator, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account_ The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account_.
     */
    function _setAccountInfo(
        address account_,
        address accountOwner,
        address initiator,
        uint256 maxClaimFee,
        bytes memory metaData_
    ) internal {
        if (maxClaimFee > 1e18) revert InvalidValue();

        accountToInitiator[accountOwner][account_] = initiator;
        // unsafe cast: maxClaimFee <= 1e18 < type(uint64).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        accountInfo[account_] = AccountInfo({ maxClaimFee: uint64(maxClaimFee) });
        metaData[account_] = metaData_;

        emit AccountInfoSet(account_, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                             CLOSING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Closes (partially) a position of an Arcadia Account.
     * @param account_ The contract address of the Account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function close(address account_, InitiatorParams calldata initiatorParams) external whenNotPaused {
        // Store Account address, used to validate the caller of the executeAction() callback and serves as a reentrancy guard.
        if (account != address(0)) revert Reentered();
        account = account_;

        // If the initiator is set, account_ is an actual Arcadia Account.
        if (accountToInitiator[IAccount(account_).owner()][account_] != msg.sender) revert InvalidInitiator();
        if (!isPositionManager(initiatorParams.positionManager)) revert InvalidPositionManager();

        // Validate initiatorParams.
        if (initiatorParams.claimFee > accountInfo[account_].maxClaimFee) revert InvalidValue();
        if (initiatorParams.withdrawAmount > initiatorParams.maxRepayAmount) revert InvalidValue();

        // If numeraire has to be withdrawn from the account, a numeraire must have been set.
        address numeraire;
        if (initiatorParams.maxRepayAmount > 0) {
            numeraire = IAccount(account_).numeraire();
            if (numeraire == address(0)) revert InvalidNumeraire();
        }

        // Encode data for the flash-action.
        bytes memory actionData = ArcadiaLogic._encodeAction(
            initiatorParams.positionManager,
            initiatorParams.id,
            numeraire,
            address(0),
            initiatorParams.withdrawAmount,
            0,
            abi.encode(msg.sender, numeraire, initiatorParams)
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
    function executeAction(bytes calldata actionTargetData)
        external
        virtual
        override
        returns (ActionData memory depositData)
    {
        // Caller should be the Account, provided as input in rebalance().
        if (msg.sender != account) revert OnlyAccount();

        // Decode actionTargetData.
        (address initiator, address numeraire, InitiatorParams memory initiatorParams) =
            abi.decode(actionTargetData, (address, address, InitiatorParams));
        address positionManager = initiatorParams.positionManager;

        // Get all pool and position related state.
        PositionState memory position = _getPositionState(positionManager, initiatorParams.id);

        // If debt has to be repaid, get the index of the numeraire in the position tokens.
        uint256 numeraireIndex;
        if (initiatorParams.maxRepayAmount > 0) {
            (position.tokens, numeraireIndex) = _getIndex(position.tokens, numeraire);
        }

        uint256[] memory balances = new uint256[](position.tokens.length);
        // withdrawAmount can only be non zero if maxRepayAmount is non zero (enforced in "close()").
        if (initiatorParams.withdrawAmount > 0) balances[numeraireIndex] = initiatorParams.withdrawAmount;
        uint256[] memory fees = new uint256[](balances.length);

        // Claim pending yields and update balances.
        _claim(balances, fees, positionManager, position, initiatorParams.claimFee);

        // Decrease liquidity or fully burn position, and update balances.
        if (initiatorParams.liquidity > 0) {
            // If the position is staked, unstake it.
            _unstake(balances, positionManager, position);

            if (initiatorParams.liquidity < position.liquidity) {
                _decreaseLiquidity(balances, positionManager, position, initiatorParams.liquidity);
                // If the position was staked, stake it.
                _stake(balances, positionManager, position);
            } else {
                _burn(balances, positionManager, position);
                position.id = 0;
            }
        }

        // Repay the debt and update balances.
        _repayDebt(balances, fees, numeraire, numeraireIndex, initiatorParams.maxRepayAmount);

        // Approve the liquidity position and leftovers to be deposited back into the Account.
        // And transfer the initiator fees to the initiator.
        uint256 count = _approveAndTransfer(initiator, balances, fees, positionManager, position);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Close(msg.sender, positionManager, initiatorParams.id);
    }

    /**
     * @notice Finds the index of a token in an array, or appends it if not found.
     * @param tokens The array of token addresses to search.
     * @param token The token address to find or add.
     * @return tokens_ The array of tokens, potentially with the new token appended.
     * @return index The index of the token in the array.
     * @dev If the token is not found, a new array is created with the token appended at the end.
     */
    function _getIndex(address[] memory tokens, address token) internal pure returns (address[] memory, uint256) {
        uint256 length = tokens.length;

        // Search for the token in the tokens array.
        for (uint256 i; i < length; i++) {
            if (token == tokens[i]) {
                return (tokens, i);
            }
        }

        // If token is not in tokens, append it to the array.
        address[] memory tokens_ = new address[](length + 1);
        for (uint256 j; j < length; j++) {
            tokens_[j] = tokens[j];
        }
        tokens_[length] = token;
        return (tokens_, length);
    }

    /* ///////////////////////////////////////////////////////////////
                            REPAY LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Repays debt to the lending pool.
     * @param balances The balances of the underlying tokens.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param numeraire The contract address of the numeraire token.
     * @param index The index of the numeraire in the balances array.
     * @param maxRepayAmount The maximum amount of numeraire to repay.
     */
    function _repayDebt(
        uint256[] memory balances,
        uint256[] memory fees,
        address numeraire,
        uint256 index,
        uint256 maxRepayAmount
    ) internal {
        // Terminate early if no repayment is needed.
        if (maxRepayAmount == 0) return;

        // Fetch the open debt on the LendingPool.
        ILendingPool lendingPool = ILendingPool(IAccount(msg.sender).creditor());
        uint256 debt = lendingPool.maxWithdraw(msg.sender);

        // The amount repaid is the minimum of the debt, the maxRepayAmount and the available balance on the closer.
        uint256 amount = _min3(maxRepayAmount, debt, balances[index] - fees[index]);

        ERC20(numeraire).safeApproveWithRetry(address(lendingPool), amount);
        lendingPool.repay(amount, msg.sender);

        balances[index] -= amount;
    }

    /**
     * @notice Returns the minimum of three uint256 values.
     * @param a The first value.
     * @param b The second value.
     * @param c The third value.
     * @return m The minimum value among a, b, and c.
     */
    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 m) {
        assembly {
            m := a
            if lt(b, m) { m := b }
            if lt(c, m) { m := c }
        }
    }

    /* ///////////////////////////////////////////////////////////////
                    APPROVE AND TRANSFER LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Approves the liquidity position and leftovers to be deposited back into the Account
     * and transfers the initiator fees to the initiator.
     * @param initiator The address of the initiator.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param fees The fees of the underlying tokens to be paid to the initiator.
     * @param positionManager The contract address of the Position Manager.
     * @param position A struct with position and pool related variables.
     * @return count The number of assets approved.
     */
    function _approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position
    ) internal returns (uint256 count) {
        // Approve the Liquidity Position.
        if (position.id > 0) {
            ERC721(positionManager).approve(msg.sender, position.id);
            count = 1;
        }

        // Transfer Initiator fees and approve the leftovers.
        address token;
        for (uint256 i; i < balances.length; i++) {
            token = position.tokens[i];
            // If there are leftovers, deposit them back into the Account.
            if (balances[i] > fees[i]) {
                balances[i] = balances[i] - fees[i];
                ERC20(token).safeApproveWithRetry(msg.sender, balances[i]);
                count++;
            } else {
                fees[i] = balances[i];
                balances[i] = 0;
            }

            // Transfer Initiator fees to the initiator.
            if (fees[i] > 0) ERC20(token).safeTransfer(initiator, fees[i]);
            emit FeePaid(msg.sender, initiator, token, fees[i]);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             SKIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Recovers any native or ERC20 tokens left on the contract.
     * @param token The contract address of the token, or address(0) for native tokens.
     */
    function skim(address token) external onlyOwner whenNotPaused {
        if (account != address(0)) revert Reentered();

        if (token == address(0)) {
            (bool success, bytes memory result) = payable(msg.sender).call{ value: address(this).balance }("");
            require(success, string(result));
        } else {
            ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
}
