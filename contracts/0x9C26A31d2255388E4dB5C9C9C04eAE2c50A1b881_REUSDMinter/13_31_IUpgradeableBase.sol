// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./16_31_IUUPSUpgradeableVersion.sol";
import "./11_31_IRECoverable.sol";
import "./10_31_IOwned.sol";

interface IUpgradeableBase is IUUPSUpgradeableVersion, IRECoverable, IOwned
{
}