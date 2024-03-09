// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./15_31_IUUPSUpgradeable.sol";

interface IUUPSUpgradeableVersion is IUUPSUpgradeable
{
    error UpgradeToSameVersion();

    function contractVersion() external view returns (uint256);
}