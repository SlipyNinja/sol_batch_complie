// SPDX-License-Identifier: MIT
// Copyright 2023 Proof Holdings Inc.

pragma solidity >=0.8.17;

import {Ownable} from "./2_15_Ownable.sol";
import {AccessControl} from "./3_15_AccessControl.sol";
import {Address} from "./4_15_Address.sol";
import {AccessControlEnumerable} from "./5_15_AccessControlEnumerable.sol";
import {ERC165} from "./6_15_ERC165.sol";

import {IAdminACLV0} from "./7_15_IAdminACLV0.sol";

contract PROOFAdminACL is AccessControlEnumerable, IAdminACLV0 {
    using Address for address;

    constructor(address admin, address steerer) AccessControlEnumerable() {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEFAULT_STEERING_ROLE, steerer);
        superAdmin = steerer;
    }

    /**
     * @notice Forwards raw calls to any address.
     */
    function call(address target, bytes calldata cdata)
        external
        payable
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bytes memory)
    {
        return target.functionCallWithValue(cdata, msg.value);
    }

    /**
     * @inheritdoc IAdminACLV0
     * @dev Steeres pass any and all ACL checks.
     */
    function allowed(
        address sender,
        address, // contract
        bytes4 // selector
    ) external view returns (bool) {
        return hasRole(DEFAULT_STEERING_ROLE, sender);
    }

    /**
     * @inheritdoc AccessControl
     * @dev Overriding to automatically clear super admin if it's role is revoked.Note that this function does not
     * emit the event to update the fronend.
     */
    function _revokeRole(bytes32 role, address account) internal virtual override {
        super._revokeRole(role, account);

        if (account == superAdmin && role == DEFAULT_STEERING_ROLE) {
            superAdmin = address(0);
        }
    }

    /**
     * @notice Changes the super admin address.
     * @dev Only members of the DEFAULT_STEERING_ROLE can be made super admin.
     */
    function changeSuperAdmin(address newSuperAdmin, address[] calldata genArt721CoreAddressesToUpdate)
        external
        onlyRole(DEFAULT_STEERING_ROLE)
    {
        _checkRole(DEFAULT_STEERING_ROLE, newSuperAdmin);

        address previousSuperAdmin = superAdmin;
        superAdmin = newSuperAdmin;
        emit SuperAdminTransferred(previousSuperAdmin, newSuperAdmin, genArt721CoreAddressesToUpdate);
    }

    // =================================================================================================================
    //                          IAdminACLV0 Compat
    // =================================================================================================================

    /**
     * @inheritdoc IAdminACLV0
     */
    string public constant AdminACLType = "PROOFAdminACL";

    /**
     * @inheritdoc IAdminACLV0
     * @dev superAdmin does not have any additional permissions in this ACL. It is needed to enable admin features on
     * the ArtBlocks frontend.
     */
    address public superAdmin;

    /**
     * @notice Calls `transferOwnership` on other contract from this contract.
     */
    function transferOwnershipOn(address ownable, address newAdminACL) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            ERC165(newAdminACL).supportsInterface(type(IAdminACLV0).interfaceId),
            "AdminACLV0: new admin ACL does not support IAdminACLV0"
        );
        Ownable(ownable).transferOwnership(newAdminACL);
    }

    /**
     * @notice Calls `renounceOwnership` on other contract from this contract.
     */
    function renounceOwnershipOn(address ownable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Ownable(ownable).renounceOwnership();
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IAdminACLV0).interfaceId || super.supportsInterface(interfaceId);
    }
}
