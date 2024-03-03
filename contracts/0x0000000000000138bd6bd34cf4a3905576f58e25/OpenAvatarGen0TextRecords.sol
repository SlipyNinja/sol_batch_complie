// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {DNATextRecord, IOpenAvatarGen0TextRecords, TextRecord} from './IOpenAvatarGen0TextRecords.sol';
import {IERC634} from './core/dependencies/IERC634.sol';
import {ENSReverseClaimer} from './core/lib/ENSReverseClaimer.sol';
import {KeepAlive} from './core/lib/KeepAlive.sol';
import {IOpenAvatarGen0TokenDNA} from './IOpenAvatarGen0Token.sol';
import {OpenAvatarGenerationZero} from './OpenAvatarGenerationZero.sol';

/**
 * @title OpenAvatarGen0TextRecords
 * @author Cory Gabrielsen (cory.eth)
 *
 * @notice This contract stores text records as key/value pairs, by 32-byte
 * OpenAvatar DNA.
 * @dev This contract is based on ERC-634 text() originally developed for ENS.
 *
 *
 * ----------------------------------------------------------------------------
 * Text Records
 * ----------------------------------------------------------------------------
 * A *Text Record* is a core building block of OpenAvatar.
 *
 * Text records are key-value pairs of strings stored onchain by Avatar DNA
 * in the `OpenAvatarGen0TextRecords` contract. Token owners may store any
 * key/value pair for their token's DNA.
 *
 * This mechanism provides an onchain key/value data store for Avatar DNA.
 *
 * Text records may be used by other contracts and applications to read/write
 * arbitrary data to an OpenAvatar.
 *
 * For example, text records are used to determine if the token owner has
 * set the background color for their Profile Picture Renderer. This allows
 * token owners to dynamically customize their Avatar onchain, and provides
 * an example for more complex integrations.
 */
contract OpenAvatarGen0TextRecords is
  IOpenAvatarGen0TextRecords,
  OpenAvatarGenerationZero,
  ENSReverseClaimer,
  KeepAlive
{
  /// @dev Error when a component is already initialized.
  error AlreadyInitialized();
  /// @dev Error when the required ERC-165 interfaces are not supported.
  error InterfaceUnsupported(address contractAddress, bytes4 interfaceId);
  /// @dev Error when the caller is not the token owner.
  error NotTokenOwner();

  /// @dev The EIP-165 interface id for the text data extension
  bytes4 private constant INTERFACE_ID_TEXT = 0x59d1d43c;
  /// @dev The ERC-165 interface id for the OpenAvatarDNA (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA = 0x2717336f;

  /// @dev An event emitted when text data is set for a DNA
  event TextChanged(bytes32 indexed dna, string indexedKey, string key);

  /// @dev The text data for each DNA
  mapping(bytes32 => mapping(string => string)) private texts;

  /// @dev The OpenAvatar contract
  IOpenAvatarGen0TokenDNA public openAvatarGen0Token;

  constructor(address ownerProxy) {
    // will be deployed by ImmutableCreate2Factory and then transferred to the
    // configured owner.
    // using a proxy allows for using same constructor args and thus same
    // bytecode for all instances of this contract.

    address wantOwner = Ownable(ownerProxy).owner();
    if (owner() != wantOwner) {
      transferOwnership(wantOwner);
    }
  }

  /////////////////////////////////////////////////////////////////////////////
  // Initialize Dependencies
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Initialize the contract.
   * @param openAvatarGen0Token_ The address of the OpenAvatar token contract.
   */
  function initialize(address openAvatarGen0Token_) external onlyOwner {
    setOpenAvatarGen0Token(openAvatarGen0Token_);
  }

  /**
   * @notice Check if the contract has been initialized.
   * @return True if the contract has been initialized, false otherwise.
   */
  function isInitialized() external view returns (bool) {
    return address(openAvatarGen0Token) != address(0);
  }

  /**
   * @dev Get the OpenAvatar token.
   * @return The address of the OpenAvatar token read interface contract.
   */
  function getOpenAvatarGen0Token() external view returns (address) {
    return address(openAvatarGen0Token);
  }

  /**
   * @dev Set the OpenAvatar token address.
   * @param openAvatarGen0Token_ The address of the OpenAvatar token contract.
   */
  function setOpenAvatarGen0Token(address openAvatarGen0Token_) internal {
    // only set once
    if (address(openAvatarGen0Token) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only DNA interface is required
    if (!IERC165(openAvatarGen0Token_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA)) {
      revert InterfaceUnsupported(openAvatarGen0Token_, INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA);
    }

    // set
    openAvatarGen0Token = IOpenAvatarGen0TokenDNA(openAvatarGen0Token_);
  }

  /////////////////////////////////////////////////////////////////////////////
  // ERC-165: Standard Interface Detection
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Checks if the contract supports an interface.
   * @param interfaceId The interface identifier, as specified in ERC-165.
   * @return True if the contract supports interfaceID, false otherwise.
   */
  function supportsInterface(bytes4 interfaceId) public pure override(OpenAvatarGenerationZero) returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // ERC634
      interfaceId == INTERFACE_ID_TEXT || // ERC165 interface ID for ERC634.
      // IOpenAvatar
      interfaceId == 0xfdf02ac8 || // ERC165 interface ID for IOpenAvatarGeneration.
      interfaceId == 0x7b65147c || // ERC165 interface ID for IOpenAvatarSentinel.
      interfaceId == 0x86953eb4 || // ERC165 interface ID for IOpenAvatar.
      // IOpenAvatarGen0TextRecords
      interfaceId == 0x8aacdebd; // ERC165 interface ID for IOpenAvatarGen0TextRecords.
  }

  /////////////////////////////////////////////////////////////////////////////
  // ERC-634 equivalent
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Retrieves text metadata for DNA.
   * Each DNA may have multiple pieces of metadata, identified by a unique string key.
   * f no text data exists for DNA with the key key, the empty string is returned.
   * @param dna The DNA to query.
   * @param key The text data key to query.
   * @return The associated text data.
   */
  function text(bytes32 dna, string calldata key) external view returns (string memory) {
    return texts[dna][key];
  }

  /////////////////////////////////////////////////////////////////////////////
  // Setters
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Sets text records for DNA with the unique key key to value,
   * overwriting anything previously stored for DNA and key. To clear a
   * text field, set it to the empty string.
   * @param dna The DNA to update.
   * @param key The key to set.
   * @param value The text data value to set.
   */
  function _setText(bytes32 dna, string calldata key, string calldata value) internal {
    texts[dna][key] = value;
    emit TextChanged(dna, key, key);
  }

  /**
   * @dev Sets text records for DNA with the unique key key to value,
   * overwriting anything previously stored for DNA and key. To clear a
   * text field, set it to the empty string.
   * Only callable by the token owner.
   * @param dna The DNA to update.
   * @param key The key to set.
   * @param value The text data value to set.
   */
  function setText(bytes32 dna, string calldata key, string calldata value) external {
    if (openAvatarGen0Token.ownerOfDNA(dna) != msg.sender) revert NotTokenOwner();
    _setText(dna, key, value);
  }

  /**
   * @dev Sets text records for DNA with the unique key key to value,
   * overwriting anything previously stored for DNA and key. To clear a
   * text field, set it to the empty string.
   * Only callable by the token owner.
   * @param dna The DNA to update.
   * @param key The key to set.
   * @param value The text data value to set.
   * @param key2 The second key to set.
   * @param value2 The second text data value to set.
   */
  function setText2(
    bytes32 dna,
    string calldata key,
    string calldata value,
    string calldata key2,
    string calldata value2
  ) external {
    if (openAvatarGen0Token.ownerOfDNA(dna) != msg.sender) revert NotTokenOwner();
    _setText(dna, key, value);
    _setText(dna, key2, value2);
  }

  /**
   * @dev Sets text records for DNA with the unique key key to value,
   * overwriting anything previously stored for DNA and key. To clear a
   * text field, set it to the empty string.
   * Only callable by the token owner.
   * @param dna The DNA to update.
   * @param key The key to set.
   * @param value The text data value to set.
   * @param key2 The second key to set.
   * @param value2 The second text data value to set.
   * @param key3 The third key to set.
   * @param value3 The third text data value to set.
   */
  function setText3(
    bytes32 dna,
    string calldata key,
    string calldata value,
    string calldata key2,
    string calldata value2,
    string calldata key3,
    string calldata value3
  ) external {
    if (openAvatarGen0Token.ownerOfDNA(dna) != msg.sender) revert NotTokenOwner();
    _setText(dna, key, value);
    _setText(dna, key2, value2);
    _setText(dna, key3, value3);
  }

  /**
   * @dev Sets text records for DNA with the unique key key to value,
   * overwriting anything previously stored for DNA and key. To clear a
   * text field, set it to the empty string.
   * Only callable by the token owner.
   * @param dna The DNA to update.
   * @param key The key to set.
   * @param value The text data value to set.
   * @param key2 The second key to set.
   * @param value2 The second text data value to set.
   * @param key3 The third key to set.
   * @param value3 The third text data value to set.
   * @param key4 The fourth key to set.

   */
  function setText4(
    bytes32 dna,
    string calldata key,
    string calldata value,
    string calldata key2,
    string calldata value2,
    string calldata key3,
    string calldata value3,
    string calldata key4,
    string calldata value4
  ) external {
    if (openAvatarGen0Token.ownerOfDNA(dna) != msg.sender) revert NotTokenOwner();
    _setText(dna, key, value);
    _setText(dna, key2, value2);
    _setText(dna, key3, value3);
    _setText(dna, key4, value4);
  }

  /**
   * @dev Sets an array of text records for a DNA. Each text record is a key/value pair.
   * Only callable by the token owner.
   * @param dna The DNA to update.
   * @param records The text records to set.
   */
  function setTexts(bytes32 dna, TextRecord[] calldata records) external {
    if (openAvatarGen0Token.ownerOfDNA(dna) != msg.sender) revert NotTokenOwner();
    uint length = records.length;
    for (uint256 i = 0; i < length; ) {
      TextRecord calldata record = records[i];
      _setText(dna, record.key, record.value);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @dev Set a batch text records where each record may be a different DNA.
   *
   * @param records The records to set.
   */
  function setTextBatch(DNATextRecord[] calldata records) external {
    uint length = records.length;
    for (uint256 i = 0; i < length; ) {
      DNATextRecord calldata record = records[i];
      if (openAvatarGen0Token.ownerOfDNA(record.dna) != msg.sender) revert NotTokenOwner();
      _setText(record.dna, record.key, record.value);
      unchecked {
        ++i;
      }
    }
  }
}
