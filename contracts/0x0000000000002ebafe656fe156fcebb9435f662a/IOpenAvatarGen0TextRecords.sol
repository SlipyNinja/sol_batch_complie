// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;
import {IERC634} from './core/dependencies/IERC634.sol';

/**
 * @title Text Record
 * @notice A key-value string pair.
 */
struct TextRecord {
  string key;
  string value;
}

/**
 * @title DNA Text Record
 * @notice A DNA and a key-value string pair.
 */
struct DNATextRecord {
  bytes32 dna;
  string key;
  string value;
}

/**
 * @title IOpenAvatarGen0TextRecords
 * @dev The TextStore contract stores text data by 32-byte OpenAvatar DNA.
 *
 * This contract is based on ERC-634 originally developed for ENS.
 */
interface IOpenAvatarGen0TextRecords is IERC634 {
  function setText(bytes32 dna, string calldata key, string calldata value) external;

  function setText2(
    bytes32 dna,
    string calldata key,
    string calldata value,
    string calldata key2,
    string calldata value2
  ) external;

  function setText3(
    bytes32 dna,
    string calldata key,
    string calldata value,
    string calldata key2,
    string calldata value2,
    string calldata key3,
    string calldata value3
  ) external;

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
  ) external;

  function setTexts(bytes32 dna, TextRecord[] calldata records) external;

  function setTextBatch(DNATextRecord[] calldata records) external;
}
