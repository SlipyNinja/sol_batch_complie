// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./17_31_Minter.sol";
import "./14_31_IUUPSERC20.sol";
import "./05_31_IBridgeable.sol";

interface IBridgeUUPSERC20 is IBridgeable, IMinter, IUUPSERC20
{
}