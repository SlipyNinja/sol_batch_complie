// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IStash} from "./interfaces/IStash.sol";
import {IStashFactory} from "./interfaces/IStashFactory.sol";

/**
 * @title StashVerifier
 * @author Yuga Labs
 * @custom:security-contact security@yugalabs.io
 * @notice Helper contract used by the StashFactory to make external calls to the Stash contract.
 */
contract StashVerifier {
    address private immutable _STASH_FACTORY_ADDRESS;

    constructor() {
        _STASH_FACTORY_ADDRESS = msg.sender;
    }

    function isStash(address stashAddress) external view returns (bool) {
        IStash stashContract = IStash(stashAddress);

        uint256 size;
        assembly {
            size := extcodesize(stashAddress)
        }
        if (size == 0) return false;

        // call owner() method on stash
        (bool success, bytes memory result) = address(stashContract).staticcall(abi.encodeWithSelector(0x8da5cb5b));
        if (!success) return false;

        address stashOwner;
        assembly {
            // extract stash owner address from result
            stashOwner := and(mload(add(result, 32)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        address predictedAddress = IStashFactory(_STASH_FACTORY_ADDRESS).stashAddressFor(stashOwner);

        // ensure that the stash owner would have deployed to the provided stashAddress
        return predictedAddress == stashAddress;
    }

    function stashVersion(address stashAddress) external view returns (uint256) {
        IStash stashContract = IStash(stashAddress);

        return stashContract.version();
    }
}
