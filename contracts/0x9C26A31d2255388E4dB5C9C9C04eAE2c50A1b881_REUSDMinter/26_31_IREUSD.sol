// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./06_31_IBridgeUUPSERC20.sol";
import "./07_31_ICanMint.sol";
import "./13_31_IUpgradeableBase.sol";

interface IREUSD is IBridgeUUPSERC20, ICanMint, IUpgradeableBase
{
    function isREUSD() external view returns (bool);
    function url() external view returns (string memory);
}