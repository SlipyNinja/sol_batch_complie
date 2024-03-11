// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./23_31_UUPSUpgradeableVersion.sol";
import "./19_31_RECoverable.sol";
import "./18_31_Owned.sol";
import "./13_31_IUpgradeableBase.sol";

abstract contract UpgradeableBase is UUPSUpgradeableVersion, RECoverable, Owned, IUpgradeableBase
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 __contractVersion)
        UUPSUpgradeableVersion(__contractVersion)
    {
    }

    function getRECoverableOwner() internal override view returns (address) { return owner(); }
    
    function beforeUpgradeVersion(address newImplementation)
        internal
        override
        view
        onlyOwner
    {
        checkUpgradeBase(newImplementation);
    }

    function checkUpgradeBase(address newImplementation) internal virtual view;
}