// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./02_06_ERC20.sol";
import "./03_06_ERC20Burnable.sol";

contract HCFC is ERC20, ERC20Burnable {
    constructor() ERC20("Humans Care Foundation: Childhood", "HCFC") {
        _mint(msg.sender, 21000000 * 10 ** decimals());
    }
}