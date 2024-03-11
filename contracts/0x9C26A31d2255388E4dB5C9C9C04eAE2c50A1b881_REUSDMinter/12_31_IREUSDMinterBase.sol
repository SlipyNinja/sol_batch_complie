// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./25_31_IREStablecoins.sol";
import "./26_31_IREUSD.sol";
import "./24_31_IRECustodian.sol";

interface IREUSDMinterBase
{
    event MintREUSD(address indexed minter, IERC20 paymentToken, uint256 reusdAmount);

    function REUSD() external view returns (IREUSD);
    function stablecoins() external view returns (IREStablecoins);
    function totalMinted() external view returns (uint256);
    function totalReceived(IERC20 paymentToken) external view returns (uint256);
    function getREUSDAmount(IERC20 paymentToken, uint256 paymentTokenAmount) external view returns (uint256 reusdAmount);
    function custodian() external view returns (IRECustodian);
}