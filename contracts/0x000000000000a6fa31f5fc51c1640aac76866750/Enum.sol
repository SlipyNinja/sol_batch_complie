// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

enum OrderType
{
    // 0: Can replace previous bid. Alters bid price and adds `numberOfUnits`
    SUBSEQUENT_BIDS_OVERWRITE_PRICE_AND_ADD_UNITS,
    // 1: Can replace previous bid if new bid has higher `pricePerUnit`
    SUBSEQUENT_BIDS_REPLACE_EXISTING_PRICE_INCREASE_REQUIRED,
    // 2: Cannot replace previous bid under any circumstance
    UNREPLACEABLE
}
