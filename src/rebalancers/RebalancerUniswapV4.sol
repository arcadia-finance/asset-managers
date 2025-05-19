/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Currency } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { PositionState } from "../state/PositionState.sol";
import { Rebalancer } from "./Rebalancer.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";
import { UniswapV4 } from "../base/UniswapV4.sol";

/**
 * @title Rebalancer for Uniswap V4 Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permissioned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 * @dev The rebalancer must not be used for Pools of native ETH - WETH.
 */
contract RebalancerUniswapV4 is Rebalancer, UniswapV4 {
    using SafeApprove for ERC20;
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param positionManager The contract address of the Uniswap v4 Position Manager.
     * @param permit2 The contract address of Permit2.
     * @param poolManager The contract address of the Uniswap v4 Pool Manager.
     * @param weth The contract address of WETH.
     */
    constructor(address arcadiaFactory, address positionManager, address permit2, address poolManager, address weth)
        Rebalancer(arcadiaFactory)
        UniswapV4(positionManager, permit2, poolManager, weth)
    { }

    /* ///////////////////////////////////////////////////////////////
                             SWAP LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one token for another, via a router with custom swap data.
     * @param balances The balances of the underlying tokens held by the Rebalancer.
     * @param position A struct with position and pool related variables.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @dev Initiator has to route swap in such a way that at least minLiquidity of liquidity is added to the position after the swap.
     * And leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
     * and the initiator fee will be 0 (but the transaction will not revert)
     */
    function _swapViaRouter(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal override {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));
        if (router == accountInfo[msg.sender].strategyHook) revert InvalidRouter();

        // Handle pools with native ETH.
        address token0 = position.tokens[0];
        bool isNative = token0 == address(0);
        if (zeroToOne && isNative) {
            token0 = WETH;
            IWETH(WETH).deposit{ value: amountIn }();
        }

        // Approve token to swap.
        ERC20(zeroToOne ? token0 : position.tokens[1]).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Handle pools with native ETH.
        if (isNative) IWETH(WETH).withdraw(ERC20(WETH).balanceOf(address(this)));

        // Update the balances, token0 might be native ETH.
        balances[0] = Currency.wrap(position.tokens[0]).balanceOfSelf();
        balances[1] = ERC20(position.tokens[1]).balanceOf(address(this));
    }
}
