// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./33_33_ContractFactory.sol";

contract $ContractFactory is ContractFactory {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor(address _contractFactory) ContractFactory(_contractFactory) {}

    receive() external payable {}
}