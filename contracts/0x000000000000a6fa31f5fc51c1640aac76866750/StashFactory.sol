// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
import {ERC1967Factory} from "./ERC1967Factory.sol";
import {StashVerifier} from "./StashVerifier.sol";
import {IStash} from "./interfaces/IStash.sol";

/**
 * @title StashFactory
 * @author Yuga Labs
 * @custom:security-contact security@yugalabs.io
 * @notice Factory contract for deploying and upgrading Stash contracts.
 */
contract StashFactory is OwnableRoles, ERC1967Factory {
    // ------------------------- EVENTS -------------------------

    /// @dev Emitted when an auction is marked as valid or invalid.
    event AuctionSet(address indexed auction, bool indexed isAuction);

    /// @dev Emitted when a new version of the Stash implementation is added.
    event VersionAdded(uint256 indexed version, address indexed implementation);

    // --------------------- CUSTOM ERRORS ---------------------

    /// @dev The given address has already deployed a stash.
    error AlreadyDeployed();

    /// @dev The deployed Stash address does not match the predicted address.
    error StashAddressMismatch();

    /// @dev The Stash is attempting to upgrade to a version it is already on.
    error AlreadyOnCurrentVersion();

    /// @dev Contract owner is attempting to add a version, but the implementation's version() function does not match.
    error InvalidVersion(uint256 expectedVersion, uint256 actualVersion);

    // ----------------- CONSTANTS & IMMUTABLES -----------------

    /// @dev StashVerifier is used as a passthrough to read from the Stash implementation since StashFactory cannot call the Stash directly
    StashVerifier private immutable _STASH_VERIFIER;

    /// @dev The role that can add new versions of the Stash implementation
    uint256 private constant _VERSION_MANAGER_ROLE = _ROLE_69;

    /// @dev The role that can mark auctions as valid or invalid
    uint256 private constant _AUCTION_MANAGER_ROLE = _ROLE_42;

    // --------------------- STORAGE ---------------------

    /// @dev a mapping of auction addresses to whether or not they have been marked as valid
    mapping(address auction => bool isValid) private auctions;

    /// @dev a mapping of Stash version numbers to Stash implementation addresses
    mapping(uint256 version => address implementation) public implementations;

    /// @dev the current version of the Stash implementation.
    uint256 public currentVersion;

    // -------------------- CONSTRUCTOR --------------------

    /**
     * @notice Deploys the first version of the Stash implementation and sets the owner to the deployer.
     */
    constructor() {
        _initializeOwner(tx.origin);

        _STASH_VERIFIER = new StashVerifier();
    }

    // --------------------- EXTERNAL ---------------------

    /**
     * @notice Deploys a new Stash contract using the current implementation, and returns the address.
     * @param _owner The owner of the new Stash contract.
     * @return deployedAddress The address of the newly deployed Stash contract.
     * @dev Deploys a new Stash contract using the current implementation. Any caller can deploy a stash for any owner.
     * for example, a mint contract can deploy a stash for a user as a part of the mint transaction.
     */
    function deployStash(address _owner) external returns (address deployedAddress) {
        uint256 codeSize;
        address predictedAddress = _predictDeterministicAddress(_salt(_owner));

        assembly {
            codeSize := extcodesize(predictedAddress)
        }

        if (codeSize > 0) revert AlreadyDeployed();

        address _implementation = implementations[currentVersion];
        bytes memory data = abi.encodeWithSignature("initialize(address)", _owner);

        deployedAddress = _deploy(_implementation, _salt(_owner), data);

        if (deployedAddress != predictedAddress) revert StashAddressMismatch();
    }

    /**
     * @notice Upgrades a Stash contract to the latest version.
     * @dev Upgrades a Stash contract to the latest version. Only callable by Stash owner. Reverts if already on the latest version
     */
    function upgradeStash() external {
        address stash = _predictDeterministicAddress(_salt(msg.sender));

        if (_isCurrent(stash)) revert AlreadyOnCurrentVersion();
        _upgrade(stash, implementations[currentVersion], _emptyData());
    }

    /**
     * @notice Flags an auction as valid or invalid.
     * @param auction The address of the auction to flag.
     * @param _isAuction Whether or not the auction is valid.
     * @dev Stash contracts can only submit bids on valid auctions.
     */
    function setAuction(address auction, bool _isAuction) external onlyOwnerOrRoles(_AUCTION_MANAGER_ROLE) {
        auctions[auction] = _isAuction;

        emit AuctionSet(auction, _isAuction);
    }

    /**
     * @notice Adds a new version of the Stash implementation. Any newly deployed stashs will use the most
     * recent version.
     * @param implementation Address of new implementation. Version number is read from the implementation and must match next version.
     */
    function addVersion(address implementation) external onlyOwnerOrRoles(_VERSION_MANAGER_ROLE) {
        uint256 expectedVersion = ++currentVersion;
        uint256 actualVersion = IStash(payable(implementation)).version();
        if (actualVersion != expectedVersion) revert InvalidVersion(expectedVersion, actualVersion);

        implementations[expectedVersion] = implementation;

        emit VersionAdded(expectedVersion, implementation);
    }

    // --------------------- VIEW ---------------------

    /**
     * @notice Returns the address of the Stash contract for a given owner, regardless of whether or not it
     * has been deployed yet.
     * @param stashOwner The owner of the Stash contract
     * @return stash The address of the Stash contract
     */
    function stashAddressFor(address stashOwner) external view returns (address) {
        return _predictDeterministicAddress(_salt(stashOwner));
    }

    /**
     * @notice Returns whether or not an auction is valid.
     * @param auctionAddress The address to check.
     */
    function isAuction(address auctionAddress) external view returns (bool) {
        return auctions[auctionAddress];
    }

    /**
     * @notice Returns whether or not a stash is valid from the perspective of the auction manager
     * this requires a separate passthrough contract because calling the stash storage contract from
     * within the auction manager will not delegate the call to the implementation.
     * @param stashAddress The address to check.
     */
    function isStash(address stashAddress) external view returns (bool) {
        return _STASH_VERIFIER.isStash(stashAddress);
    }

    /**
     * @notice Returns whether or not a stash has been deployed for a given owner.
     * @param owner An address to check.
     * @dev This function is meant for convenience. It uses extcodesize to check if a contract has been deployed to the
     * predicted address. It is not a perfect check, and will return false if called from within a constructor of a Stash.
     */
    function ownerHasDeployed(address owner) external view returns (bool) {
        uint256 codeSize;
        address predictedAddress = _predictDeterministicAddress(_salt(owner));

        assembly {
            codeSize := extcodesize(predictedAddress)
        }

        return codeSize > 0;
    }

    /**
     * @notice Returns the stash verifier address
     */
    function stashVerifier() external view returns (address) {
        return address(_STASH_VERIFIER);
    }

    // --------------------- INTERNAL VIEW ---------------------

    function _isCurrent(address stash) internal view returns (bool) {
        return _STASH_VERIFIER.stashVersion(stash) == currentVersion;
    }

    function _salt(address stashOwner) internal pure returns (bytes32 salt) {
        bytes32 phrase = keccak256(abi.encodePacked("GAGAGGA GEEEE GOGOGOGGGO"));
        bytes12 extraData = bytes12(phrase);

        salt = bytes32((uint256(uint160(stashOwner)) << 96) | uint96(extraData));
    }
}
