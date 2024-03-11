// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./28_33_ITokenCreator.sol";

abstract contract $ITokenCreator is ITokenCreator {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}