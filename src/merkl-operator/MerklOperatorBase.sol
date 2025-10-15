/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { Guardian } from "../guardian/Guardian.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IArcadiaFactory } from "../interfaces/IArcadiaFactory.sol";
import { IDistributor } from "./interfaces/IDistributor.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";

/**
 * @title Automatic claimer of Merkl rewards for Base.
 * @author Pragma Labs
 */
contract MerklOperatorBase is Guardian, ReentrancyGuard {
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

    // A mapping from account to custom metadata.
    mapping(address account => bytes data) public metaData;

    // A mapping that sets the approved initiator per owner per account.
    mapping(address accountOwner => mapping(address account => address initiator)) public accountToInitiator;

    // A struct with the initiator parameters.
    struct InitiatorParams {
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
    error InvalidInitiator();
    error NotAnAccount();
    error OnlyAccountOwner();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event AccountInfoSet(address indexed account, address indexed initiator);

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

        (address initiator, bytes memory metaData_) = abi.decode(data, (address, bytes));
        _setAccountInfo(msg.sender, accountOwner, initiator, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account The contract address of the Arcadia Account to set the information for.
     * @param initiator The address of the initiator.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function setAccountInfo(address account, address initiator, bytes calldata metaData_) external nonReentrant {
        if (!ARCADIA_FACTORY.isAccount(account)) revert NotAnAccount();
        address accountOwner = IAccount(account).owner();
        if (msg.sender != accountOwner) revert OnlyAccountOwner();
        // Block Account versions without cross account reentrancy guard.
        if (IAccount(account).ACCOUNT_VERSION() < 3) revert InvalidAccountVersion();

        _setAccountInfo(account, accountOwner, initiator, metaData_);
    }

    /**
     * @notice Sets the required information for an Account.
     * @param account The contract address of the Arcadia Account to set the information for.
     * @param accountOwner The current owner of the Arcadia Account.
     * @param initiator The address of the initiator.
     * @param metaData_ Custom metadata to be stored with the account.
     */
    function _setAccountInfo(address account, address accountOwner, address initiator, bytes memory metaData_)
        internal
    {
        accountToInitiator[accountOwner][account] = initiator;
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

        uint256 length = initiatorParams.tokens.length;
        address[] memory users = new address[](length);
        for (uint256 i; i < length; i++) {
            // Add account to users array.
            users[i] = account;
        }

        // Claim Merkl rewards.
        // Rewards are automatically transferred to the account with the current Merkl Distributor deployed on base.
        MERKL_DISTRIBUTOR.claim(users, initiatorParams.tokens, initiatorParams.amounts, initiatorParams.proofs);
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
