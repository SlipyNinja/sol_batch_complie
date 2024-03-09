/*
 * SPDX-License-Identitifer:    MIT
 */
pragma solidity ^0.8.19;

import "./2_15_ERC721.sol";
import "./8_15_Counters.sol";
import "./1_15_Ownable.sol";
import "./10_15_ECDSA.sol";

/**
 * @title           AragonEagle
 * @author          Aragon
 *
 * Aragon Eagle NFT
 */
contract AragonEagle is ERC721, Ownable {
    using ECDSA for bytes32;
    using Counters for Counters.Counter;

    /**
     * @dev Event for setting baseURI
     */
    event SetBaseURI(string newBaseUri);

    /**
     * @dev Event for setting signature address
     */
    event SetSignatureAddress(address newSignatureAddress);

    /**
     * @dev Signature address to generate signatures
     */
    address public signatureAddress;

    /**
     * @dev Maximum tokens that can be minted
     */
    uint256 internal constant _MAX_SUPPLY = 2 ** 256 - 1;

    /**
     * @dev Last minted token
     */
    Counters.Counter internal _currentSupply;

    /**
     * @dev Base URI for token metadata
     */
    string internal _baseTokenURI;

    constructor(
        address signatureAddress_,
        string memory baseURI_
    ) ERC721("Aragon Contributor Eagles", "ARAGONEAGLE") {
        signatureAddress = signatureAddress_;
        emit SetSignatureAddress(signatureAddress);

        _baseTokenURI = baseURI_;
        emit SetBaseURI(_baseTokenURI);
    }

    /**
     * @dev Total number of minted tokens
     */
    function totalSupply() external view returns (uint256) {
        return _currentSupply.current();
    }

    /**
     * @dev Get base token URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Set the base token URI
     */
    function setBaseURI(
        string memory baseURI_
    ) external onlyOwner returns (string memory) {
        _baseTokenURI = baseURI_;

        emit SetBaseURI(baseURI_);

        return _baseTokenURI;
    }

    /**
     * @dev Mint a new Aragon Eagle Token.
     *
     * Requirements:
     *
     * - A `signature` from the server to verify the user is allowed to mint
     * - A `signatureExpiration` indicating when the signature expires
     */
    function mintAragonEagle(
        bytes memory signature,
        uint256 signatureExpiration
    ) external payable returns (uint256) {
        require(
            _verifySignature(
                keccak256(
                    abi.encodePacked(
                        "AragonEagleMintApproval",
                        msg.sender,
                        signatureExpiration,
                        block.chainid
                    )
                ),
                signature
            ),
            "The mint signature is invalid"
        );

        require(
            signatureExpiration > block.timestamp,
            "The signature is expired"
        );

        require(
            _currentSupply.current() < _MAX_SUPPLY,
            "The aragon contributor token limit has been reached"
        );

        require(
            balanceOf(msg.sender) == uint256(0),
            "An aragon contributor token already exists for this wallet"
        );

        _currentSupply.increment();
        uint256 newTokenId = _currentSupply.current();

        _mint(msg.sender, newTokenId);

        return newTokenId;
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Additional Requirements:
     *
     * - Only contract owner may manage tokens
     */
    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view virtual override returns (bool) {
        return spender == owner();
    }

    /**
     * @dev Update signature address
     */
    function updateSignatureAddress(
        address newSignatureAddress
    ) external onlyOwner {
        signatureAddress = newSignatureAddress;

        emit SetSignatureAddress(signatureAddress);
    }

    /**
     * @dev Verify signature provided to contract call. Only
     * verified Aragon contributors will be able to generate signatures.
     */
    function _verifySignature(
        bytes32 messageHash,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 signedMessageHash = messageHash.toEthSignedMessageHash();

        (
            address signedMessageHashAddress,
            ECDSA.RecoverError error
        ) = signedMessageHash.tryRecover(signature);

        if (error == ECDSA.RecoverError.NoError) {
            return signedMessageHashAddress == signatureAddress;
        } else {
            return false;
        }
    }

    /**
     * @dev Burn token, only allowed by contract owner
     */
    function burn(uint256 tokenId) external onlyOwner {
        super._burn(tokenId);
    }
}
