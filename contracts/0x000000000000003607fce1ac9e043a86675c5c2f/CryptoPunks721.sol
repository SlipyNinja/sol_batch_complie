// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {IStashFactory} from "../interfaces/IStashFactory.sol";
import {ICryptoPunks} from "../interfaces/ICryptoPunks.sol";
import {IStash} from "../interfaces/IStash.sol";
import {ILegacyWrappedPunks} from "../interfaces/ILegacyWrappedPunks.sol";
import {CryptoPunks721Metadata} from "./CryptoPunks721Metadata.sol";
import {Base64} from "solady/utils/Base64.sol";
import {ERC721} from "solady/tokens/ERC721.sol";

/**
 * @title CryptoPunks721
 * @notice A modern wrapper to enable ERC721 functionality for CryptoPunks.
 */
contract CryptoPunks721 is ERC721, CryptoPunks721Metadata {
    error NotPunkOwner();
    error PunkIsOwned();

    IStashFactory private immutable _stashFactory;
    ICryptoPunks internal immutable _cryptoPunks;
    ILegacyWrappedPunks internal immutable _legacyWrapper;

    constructor(address stashFactory, address cryptoPunks, address legacyWrapper, address _punksMetadata)
        CryptoPunks721Metadata(_punksMetadata)
    {
        _stashFactory = IStashFactory(stashFactory);
        _cryptoPunks = ICryptoPunks(cryptoPunks);
        _legacyWrapper = ILegacyWrappedPunks(legacyWrapper);
    }

    function name() public pure override returns (string memory) {
        return "CryptoPunks 721";
    }

    function symbol() public pure override returns (string memory) {
        return unicode"Ͼ721";
    }

    function licensingTerms() public pure returns (string memory) {
        return "https://licenseterms.cryptopunks.app/";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // allow retrieving metadata for all valid wrapped punks, even if not (currently) wrapped.
        if (tokenId >= 10000) {
            revert TokenDoesNotExist();
        }
        return string.concat("data:application/json;base64,", Base64.encode(bytes(stringURI(tokenId))));
    }

    /**
     * @notice Wrap a CryptoPunk. Requires that the user has transferred their punk to their Stash.
     * @dev If the user does not have a Stash, one will be deployed for them.
     * @param punkIndex The index of the punk to wrap.
     */
    function wrapPunk(uint256 punkIndex) external {
        address stash = _stashFactory.stashAddressFor(msg.sender);

        uint256 size;
        assembly {
            size := extcodesize(stash)
        }

        if (size == 0) {
            _stashFactory.deployStash(msg.sender);
        }

        IStash(stash).wrapPunk(punkIndex);
        _mint(msg.sender, punkIndex);
    }

    /**
     * @notice Wrap multiple CryptoPunks. Requires that the user has transferred their punks to their Stash.
     * @dev If the user does not have a Stash, one will be deployed for them.
     * @param punkIndexes An array of indexes of punks to wrap.
     */
    function wrapPunkBatch(uint256[] calldata punkIndexes) external {
        address stash = _stashFactory.stashAddressFor(msg.sender);

        uint256 size;
        assembly {
            size := extcodesize(stash)
        }

        if (size == 0) {
            _stashFactory.deployStash(msg.sender);
        }

        for (uint256 i = 0; i < punkIndexes.length; ++i) {
            uint256 punkIndex = punkIndexes[i];

            IStash(stash).wrapPunk(punkIndex);
            _mint(msg.sender, punkIndex);
        }
    }

    /**
     * @notice Unwrap a CryptoPunk. Requires that the caller owns or is approved to transfer the wrapped CryptoPunk.
     * @param punkIndex The index of the punk to unwrap
     */
    function unwrapPunk(uint256 punkIndex) external {
        _burn(msg.sender, punkIndex);
        _cryptoPunks.transferPunk(msg.sender, punkIndex);
    }

    /**
     * @notice Unwrap multiple CryptoPunks. Requires that the caller owns or is approved to transfer the wrapped CryptoPunks.
     * @param punkIndexes An array of indexes of punks to unwrap
     */
    function unwrapPunkBatch(uint256[] calldata punkIndexes) external {
        for (uint256 i = 0; i < punkIndexes.length; i++) {
            uint256 punkIndex = punkIndexes[i];

            _burn(msg.sender, punkIndex);
            _cryptoPunks.transferPunk(msg.sender, punkIndex);
        }
    }

    /**
     * @notice Bulk migration tool to move legacy wrapped punks into the new wrapper.
     * @param punkIndexes The indexes of the punks to migrate. Must be owned by the caller.
     */
    function migrateLegacyWrappedPunks(uint256[] calldata punkIndexes) external {
        for (uint256 i = 0; i < punkIndexes.length; ++i) {
            uint256 punkIndex = punkIndexes[i];
            _legacyWrapper.transferFrom(msg.sender, address(this), punkIndex);
            _legacyWrapper.burn(punkIndex);
            _mint(msg.sender, punkIndex);
        }
    }

    /**
     * @dev Used for rescuing punks stuck in the contract, which would otherwise be trapped.
     * Punks that are properly wrapped can NOT be "rescued". This is open to the public so that
     * CryptoPunks Wrapped can remain open and ownerless. The alternatives are to either assign
     * an owner to the contract to manage withdrawing mistakenly deposited CryptoPunks, or to
     * allow the CryptoPunks to be trapped forever. Both of these alternatives were deemed
     * less desirable.
     */
    function rescuePunk(uint256 punkIndex) external {
        if (_exists(punkIndex)) revert PunkIsOwned();
        _cryptoPunks.transferPunk(msg.sender, punkIndex);
    }

    /**
     * @notice Returns the address of the Stash for a given user.
     * @param user The user to get the Stash for.
     */
    function punkProxyForUser(address user) external view returns (address) {
        return _stashFactory.stashAddressFor(user);
    }

    /**
     * @notice Adapted from https://github.com/chiru-labs/ERC721A/blob/main/contracts/extensions/ERC721AQueryable.sol
     * @dev Returns an array of token IDs owned by `owner`.
     *
     * This function scans the ownership mapping and is O(`totalSupply`) in complexity.
     * It is meant to be called off-chain.
     */
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        unchecked {
            uint256 tokenIdsIdx;
            uint256 tokenIdsLength = balanceOf(owner);
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);

            for (uint256 i = 0; tokenIdsIdx != tokenIdsLength; ++i) {
                address tokenOwner = _ownerOf(i);
                if (tokenOwner == owner) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }

    /**
     * @notice Returns the total number of CryptoPunks that have been wrapped.
     * @dev This total can be off if punks have been mistakenly deposited to the wrapper contract.
     * However, any mistakenly deposited punks are free to be withdrawn by anybody and thus should
     * theoretically not last in the contract for more than a block.
     */
    function totalSupply() external view returns (uint256) {
        return _cryptoPunks.balanceOf(address(this)); 
    }
}
