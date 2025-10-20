// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8;

/// @title CoW Protocol Hooks Trampoline
/// @dev A trampoline contract for calling user-specified hooks. It ensures that
/// user-specified calls are not executed from a privileged context, and that
/// reverts do not prevent settlements from executing.
/// @author CoW Developers
contract HooksTrampoline {
    /// @dev A user-specified hook.
    struct Hook {
        address target;
        bytes callData;
        uint256 gasLimit;
    }

    /// @dev Error indicating that the trampoline was not called from the CoW
    /// Protocol settlement contract.
    error NotASettlement();

    /// forge-lint: disable-next-item(screaming-snake-case-immutable)
    /// @dev The address of the CoW Protocol settlement contract.
    address public immutable settlement;

    /// @param settlement_ The address of the CoW protocol settlement contract.
    constructor(address settlement_) {
        settlement = settlement_;
    }

    /// @dev Modifier that ensures that the `msg.sender` is the CoW Protocol
    /// settlement contract. Methods with this modifier are guaranteed to only
    /// be called as part of a CoW Protocol settlement.
    modifier onlySettlement() {
        if (msg.sender != settlement) {
            revert NotASettlement();
        }
        _;
    }

    /// @dev Executes the specified hooks. This function will revert if not
    /// called by the CoW Protocol settlement contract. This allows hooks to be
    /// semi-permissioned, ensuring that they are only executed as part of a CoW
    /// Protocol settlement. Additionally, hooks are called with a gas limit,
    /// and are allowed to revert. This is done in order to prevent badly
    /// configured user-specified hooks from consuming more gas than expected
    /// (for example, if a hook were to revert with an `INVALID` opcode) or
    /// causing an otherwise valid settlement to revert, effectively
    /// DoS-ing other orders.
    /// Note: The trampoline tries to ensure that the hook is called with
    /// exactly the gas limit specified in the hook, however in some
    /// circumstances it may be a bit smaller than that. This is because the
    /// algorithm to determine the gas to forward doesn't account for the gas
    /// overhead between the gas reading and call execution.
    ///
    /// @param hooks The hooks to execute.
    function execute(Hook[] calldata hooks) external onlySettlement {
        // Array bounds and overflow checks are not needed here, as `i` will
        // never overflow and `hooks[i]` will never be out of bounds as `i` is
        // smaller than `hooks.length`.
        unchecked {
            Hook calldata hook;
            for (uint256 i; i < hooks.length; ++i) {
                hook = hooks[i];
                // A call forwards all but 1/64th of the available gas. The
                // math is used as a heuristic to account for this.
                uint256 forwardedGas = gasleft() * 63 / 64;
                if (forwardedGas < hook.gasLimit) {
                    revertByWastingGas();
                }

                (bool success,) = hook.target.call{ gas: hook.gasLimit }(hook.callData);

                // In order to prevent custom hooks from DoS-ing settlements, we
                // explicitly allow them to revert.
                success;
            }
        }
    }

    /// @dev Burn all gas forwarded to the call. It's used to trigger an
    /// out-of-gas error on revert, which some node implementations (notably
    /// Nethermind) need to properly estimate the gas limit of a transaction
    /// involving this call. If gas isn't wasted or wasted through other means
    /// (for example, using `assembly { invalid() }`) then an affected node will
    /// incorrectly estimate (through `eth_estimateGas`) the gas needed by the
    /// transaction: it will return gas used in a successful transaction instead
    /// of the gas _limit_ used in the successful transaction. This is an issue
    /// for transactions that take less gas when reverting than when succeeding.
    function revertByWastingGas() private pure {
        while (true) { }
    }
}
