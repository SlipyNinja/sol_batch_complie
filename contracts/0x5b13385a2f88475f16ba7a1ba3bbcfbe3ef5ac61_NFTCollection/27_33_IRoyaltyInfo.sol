// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./10_33_IRoyaltyInfo.sol";

abstract contract $IRoyaltyInfo is IRoyaltyInfo {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}