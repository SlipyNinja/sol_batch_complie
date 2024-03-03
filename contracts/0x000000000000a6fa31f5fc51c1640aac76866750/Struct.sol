// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OrderType} from "./Enum.sol";

struct Order {
    uint16 numberOfUnits;
    uint80 pricePerUnit;
    address auction;
}

struct PunkBid {
    Order order;
    uint256 accountNonce;
    uint256 bidNonce;
    uint256 expiration;
    bytes32 root;
}
