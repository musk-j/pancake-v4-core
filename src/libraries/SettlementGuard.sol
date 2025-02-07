// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @notice This is a workaround when transient keyword is absent. It manages:
///  - 0: address locker
///  - 1: uint256 unsettledDeltasCount
///  - 2: mapping(address, mapping(Currency => int256)) currencyDelta
library SettlementGuard {
    // uint256 constant LOCKER_SLOT = uint256(keccak256("SETTLEMENT_LOCKER")) - 1;
    uint256 internal constant LOCKER_SLOT = 0xedda7c051899c54dd66eaf5e13c031326ab4729812a579bed198ab93fd313d70;

    // uint256 constant UNSETTLED_DELTAS_COUNT = uint256(keccak256("SETTLEMENT_UNSETTLEMENTD_DELTAS_COUNT")) - 1;
    uint256 internal constant UNSETTLED_DELTAS_COUNT =
        0xa88ffc6a483ae852b901fb1c3a0df606e2e4461b493434e6643ebdc3ffabd151;

    // uint256 constant CURRENCY_DELTA = uint256(keccak256("SETTLEMENT_CURRENCY_DELTA")) - 1;
    uint256 internal constant CURRENCY_DELTA = 0x6dc13502b9ba2a9e8e42c53a1856d632b29d5aab3bcb4a2476bfec06cbd9cf22;

    function setLocker(address newLocker) internal {
        address currentLocker = getLocker();

        // either set from non-zero to zero (set) or from zero to non-zero (reset)
        if (currentLocker == newLocker) return;
        if (currentLocker != address(0) && newLocker != address(0)) revert IVault.LockerAlreadySet(currentLocker);

        assembly ("memory-safe") {
            tstore(LOCKER_SLOT, newLocker)
        }
    }

    function getLocker() internal view returns (address locker) {
        assembly ("memory-safe") {
            locker := tload(LOCKER_SLOT)
        }
    }

    function getUnsettledDeltasCount() internal view returns (uint256 count) {
        assembly ("memory-safe") {
            count := tload(UNSETTLED_DELTAS_COUNT)
        }
    }

    function accountDelta(address settler, Currency currency, int256 newlyAddedDelta) internal {
        if (newlyAddedDelta == 0) return;

        /// @dev update the count of non-zero deltas if necessary
        int256 currentDelta = getCurrencyDelta(settler, currency);
        int256 nextDelta = currentDelta + newlyAddedDelta;
        unchecked {
            if (nextDelta == 0) {
                assembly ("memory-safe") {
                    tstore(UNSETTLED_DELTAS_COUNT, sub(tload(UNSETTLED_DELTAS_COUNT), 1))
                }
            } else if (currentDelta == 0) {
                assembly ("memory-safe") {
                    tstore(UNSETTLED_DELTAS_COUNT, add(tload(UNSETTLED_DELTAS_COUNT), 1))
                }
            }
        }

        /// @dev ref: https://docs.soliditylang.org/en/v0.8.24/internals/layout_in_storage.html#mappings-and-dynamic-arrays
        /// simulating mapping index but with a single hash
        /// save one keccak256 hash compared to built-in nested mapping
        uint256 elementSlot = uint256(keccak256(abi.encode(settler, currency, CURRENCY_DELTA)));
        assembly ("memory-safe") {
            tstore(elementSlot, nextDelta)
        }
    }

    function getCurrencyDelta(address settler, Currency currency) internal view returns (int256 delta) {
        uint256 elementSlot = uint256(keccak256(abi.encode(settler, currency, CURRENCY_DELTA)));
        assembly ("memory-safe") {
            delta := tload(elementSlot)
        }
    }
}
