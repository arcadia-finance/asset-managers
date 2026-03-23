/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { Closer } from "./Closer.sol";
import { PositionState } from "../state/PositionState.sol";
import { UniswapV4 } from "../base/UniswapV4.sol";

/**
 * @title Closer for Uniswap V4 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Closer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the closing functionality for a Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to close the positions in their Account.
 * Closing can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The closing will collect the fees earned by a position and decrease or fully burn the liquidity of the position.
 * It can also repay debt to the lending pool if needed.
 */
contract CloserUniswapV4 is Closer, UniswapV4 {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The version of the Asset Manager.
    string public constant VERSION = "1.0.0";

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param positionManager The contract address of the Uniswap v4 Position Manager.
     * @param permit2 The contract address of Permit2.
     * @param poolManager The contract address of the Uniswap v4 Pool Manager.
     * @param weth The contract address of WETH.
     */
    constructor(
        address owner_,
        address arcadiaFactory,
        address positionManager,
        address permit2,
        address poolManager,
        address weth
    ) Closer(owner_, arcadiaFactory) UniswapV4(positionManager, permit2, poolManager, weth) { }

    /* //////////////////////////////////////////////////////////////
                            ACTION LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Callback function called by the Arcadia Account during the flashAction.
     * @param actionTargetData A bytes object containing the initiator and initiatorParams.
     * @return depositData A struct with the asset data of the Liquidity Position and with the leftovers after mint, if any.
     * @dev The Liquidity Position is already transferred to this contract before executeAction() is called.
     * @dev Overrides base Closer to always call _stake() to wrap native ETH to WETH.
     */
    function executeAction(bytes calldata actionTargetData) external override returns (ActionData memory depositData) {
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
            if (initiatorParams.liquidity < position.liquidity) {
                _decreaseLiquidity(balances, positionManager, position, initiatorParams.liquidity);
            } else {
                _burn(balances, positionManager, position);
                position.id = 0;
            }
        }

        // If token0 was native ETH, wrap it to WETH.
        _stake(balances, positionManager, position);

        // Repay the debt and update balances.
        _repayDebt(balances, fees, numeraire, numeraireIndex, initiatorParams.maxRepayAmount);

        // Approve the liquidity position and leftovers to be deposited back into the Account.
        // And transfer the initiator fees to the initiator.
        uint256 count = _approveAndTransfer(initiator, balances, fees, positionManager, position);

        // Encode deposit data for the flash-action.
        depositData = ArcadiaLogic._encodeDeposit(positionManager, position.id, position.tokens, balances, count);

        emit Close(msg.sender, positionManager, initiatorParams.id);
    }
}
