// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {Version} from "create/contracts/v1/Version.sol";
import {IMintModuleRegistry} from "create/interfaces/v1/IMintModuleRegistry.sol";

contract MintModuleRegistry is IMintModuleRegistry, Ownable, Version {
    constructor() Version(1) {
        _initializeOwner(tx.origin);
    }

    /// @inheritdoc IMintModuleRegistry
    mapping(address => bool) public isRegistered;

    /// @inheritdoc IMintModuleRegistry
    function addModule(address module) external onlyOwner {
        if (module == address(0)) revert InvalidAddress();
        if (isRegistered[module]) revert AlreadyRegistered();

        isRegistered[module] = true;
        emit ModuleAdded(module);
    }

    /// @inheritdoc IMintModuleRegistry
    function removeModule(address module) external onlyOwner {
        if (module == address(0)) revert InvalidAddress();
        if (!isRegistered[module]) revert NotRegistered();

        delete isRegistered[module];
        emit ModuleRemoved(module);
    }

    /// @inheritdoc IMintModuleRegistry
    function checkModule(address mintModule) external view override {
        if (!isRegistered[mintModule]) revert NotRegistered();
    }
}
