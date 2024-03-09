// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./25_33_IGetFees.sol";

abstract contract $IGetFees is IGetFees {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}