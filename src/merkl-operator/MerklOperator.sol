/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Guardian } from "../guardian/Guardian.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IDistributor } from "./interfaces/IDistributor.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";

/**
 * @title Automatic claimer of Merkl rewards.
 * @author Pragma Labs
 */
contract MerklOperator is Guardian, ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Arcadia Factory.
    IArcadiaFactory public immutable ARCADIA_FACTORY;

    // The contract address of the Merkl Distributor.
    IDistributor public immutable MERKL_DISTRIBUTOR;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from account to account specific information.
    mapping(address account => AccountInfo) public accountInfo;

    // A mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account.
    mapping(address accountOwner => mapping(address account => address initiator)) public accountToInitiator;

    // A struct with the account specific parameters.
    struct AccountInfo {
        // The address of the recipient of the claimed rewards.
        address rewardRecipient;
        // The maximum fee charged on the claimed Merkl rewards, with 18 decimals precision.
        uint64 maxClaimFee;
    }

    // A struct with the initiator parameters.
    struct InitiatorParams {
        // The fee charged on the claimed Merkl rewards, with 18 decimals precision.
        uint256 claimFee;
        // Array of tokens the Merkl rewards are claimed for.
        address[] tokens;
        // Array with corresponding cumulative reward amounts.
        uint256[] amounts;
        // Array with corresponding arrays of Merkl proofs.
        bytes32[][] proofs;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidAccountVersion();
    error InvalidClaimRecipient();
    error InvalidInitiator();
    error InvalidRewardRecipient();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccountOwner();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator);
    event FeePaid(address indexed account, address indexed receiver, address indexed asset, uint256 amount);
    event YieldClaimed(address indexed account, address indexed asset, uint256 amount);
    event YieldTransferred(address indexed account, address indexed receiver, address indexed asset, uint256 amount);

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param factory The contract address of the Arcadia Accounts Factory.
     * @param merklDistributor The contract address of the Merkl Distributor.
     */
    constructor(address owner_, address factory, address merklDistributor) Guardian(owner_) {
        ARCADIA_FACTORY = IArcadiaFactory(factory);
        MERKL_DISTRIBUTOR = IDistributor(merklDistributor);
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Optional hook called by the Arcadia Account when calling "setMerklOperator()".
     * @param accountOwner The current owner of the Arcadia Account.
     * param status Bool indicating if the Operator is enabled or disabled.
     * @param data Operator specific data, passed by the Account owner.
     * @dev No need to check that the Account version is 3 or greater (versions with cross account reentrancy guard),
     * since version 1 and 2 don't support the onSetAssetManager hook.
     */
    function onSetMerklOperator(address accountOwner, bool, bytes calldata data) external nonReentrant {
        if (!ARCADIA_FACTORY.isAccount(msg.sender)) revert NotAnAccount();

        (address initiator, address rewardRecipient, uint256 maxClaimFee, bytes memory metaData_) =
            abi.decode(data, (address, address, uint256, bytes));
        _setAccountInfo(msg.sender, accountOwner, initiator, rewardRecipient, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param rewardRecipient The address of the recipient of the claimed Merkl rewards.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(
        address account,
        address initiator,
        address rewardRecipient,
        uint256 maxClaimFee,
        bytes calldata metaData_
    ) external nonReentrant {
        if (!ARCADIA_FACTORY.isAccount(account)) revert NotAnAccount();
        address accountOwner = IAccount(account).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();
        // Block Account versions without cross account reentrancy guard.
        if (IAccount(account).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account, accountOwner, initiator, rewardRecipient, maxClaimFee, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param rewardRecipient The address of the recipient of the claimed Merkl rewards.
     * @param maxClaimFee The maximum fee charged on the claimed fees of the liquidity position, with 18 decimals precision.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function _setAccountInfo(
        address account,
        address accountOwner,
        address initiator,
        address rewardRecipient,
        uint256 maxClaimFee,
        bytes memory metaData_
    ) internal {
        if (rewardRecipient == address(0)) revert InvalidRewardRecipient();
        if (maxClaimFee > 1e18) revert InvalidValue();

        accountToInitiator[accountOwner][account] = initiator;
        // unsafe cast: maxClaimFee <= 1e18 < type(uint64).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        accountInfo[account] = AccountInfo({ rewardRecipient: rewardRecipient, maxClaimFee: uint64(maxClaimFee) });
        metaData[account] = metaData_;

        emit AccountInfoSet(account, initiator);
    }

    /* ///////////////////////////////////////////////////////////////
                             CLAIMING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims Merkl rewards, owned by an Arcadia Account.
     * @param account The contract address of the account.
     * @param initiatorParams A struct with the initiator parameters.
     */
    function claim(address account, InitiatorParams calldata initiatorParams) external whenNotPaused nonReentrant {
        // If the initiator is set, account is an actual Arcadia Account.
        if (accountToInitiator[IAccount(account).owner()][account] != msg.sender) revert InvalidInitiator();

        // Validate initiatorParams.
        // No need to check length arrays, as it is checked in _claim() on Distributor.
        uint256 claimFee = initiatorParams.claimFee;
        if (initiatorParams.claimFee > accountInfo[account].maxClaimFee) revert InvalidValue();

        uint256 length = initiatorParams.tokens.length;
        uint256[] memory balances = new uint256[](length);
        address[] memory users = new address[](length);
        address token;
        for (uint256 i; i < length; i++) {
            token = initiatorParams.tokens[i];

            // Check that Operator is recipient for each token.
            if (MERKL_DISTRIBUTOR.claimRecipient(account, token) != address(this)) revert InvalidClaimRecipient();

            // Cache balances for each token.
            balances[i] = ERC20(token).balanceOf(address(this));

            // Add account to users array.
            users[i] = account;
        }

        // Claim Merkl rewards.
        MERKL_DISTRIBUTOR.claim(users, initiatorParams.tokens, initiatorParams.amounts, initiatorParams.proofs);

        // Transfer rewards to recipient and fees to initiator.
        address rewardRecipient = accountInfo[account].rewardRecipient;
        uint256 reward;
        uint256 fee;
        for (uint256 j; j < length; j++) {
            token = initiatorParams.tokens[j];

            reward = ERC20(token).balanceOf(address(this)) - balances[j];
            // Shortcut iteration if rewards is 0.
            if (reward == 0) continue;
            emit YieldClaimed(account, token, reward);

            fee = reward.mulDivDown(claimFee, 1e18);
            reward = reward - fee;

            // Send the reward to the rewardRecipient.
            if (reward > 0) {
                ERC20(token).safeTransfer(rewardRecipient, reward);
                emit YieldTransferred(account, rewardRecipient, token, reward);
            }

            // Transfer Initiator fees to the initiator.
            if (fee > 0) {
                ERC20(token).safeTransfer(msg.sender, fee);
                emit FeePaid(account, msg.sender, token, fee);
            }
        }
    }

    /* ///////////////////////////////////////////////////////////////
                             SKIM LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Recovers any native or ERC20 tokens left on the contract.
     * @param token The contract address of the token, or address(0) for native tokens.
     */
    function skim(address token) external onlyOwner whenNotPaused nonReentrant {
        if (token == address(0)) {
            (bool success, bytes memory result) = payable(msg.sender).call{ value: address(this).balance }("");
            require(success, string(result));
        } else {
            ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
}
