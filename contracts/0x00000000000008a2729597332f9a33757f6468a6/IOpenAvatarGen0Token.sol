// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IOpenAvatar} from './IOpenAvatar.sol';

/**
 * @title OpenAvatarGen0TokenMetadata
 * @dev The OpenAvatar metadata.
 */
struct OpenAvatarGen0TokenMetadata {
  uint generation;
  uint tokenId;
  bytes32 dna;
  address creator;
  address renderer;
}

/**
 * @title IOpenAvatarGen0TokenMetadata
 * @dev An interface for the OpenAvatar metadata.
 */
interface IOpenAvatarGen0TokenMetadata {
  function getOpenAvatarGen0TokenMetadataByDNA(bytes32 dna) external view returns (OpenAvatarGen0TokenMetadata memory);

  function getOpenAvatarGen0TokenMetadataByTokenId(
    uint tokenId
  ) external view returns (OpenAvatarGen0TokenMetadata memory);

  function openAvatarURI(bytes32 dna) external view returns (string memory);
}

/**
 * @title IOpenAvatarGen0TokenDNA
 * @dev An interface for the OpenAvatar DNA.
 */
interface IOpenAvatarGen0TokenDNA {
  function getDNAByTokenId(uint tokenId) external view returns (bytes32);

  function getDNAsByTokenIds(uint[] calldata tokenIds) external view returns (bytes32[] memory);

  function getTokenIdByDNA(bytes32 dna) external view returns (uint);

  function getTokenIdsByDNAs(bytes32[] calldata dnas) external view returns (uint[] memory);

  function creatorOf(uint tokenId) external view returns (address);

  function creatorOfDNA(bytes32 dna) external view returns (address);

  function ownerOfDNA(bytes32 dna) external view returns (address);

  function ownerOfDNAs(bytes32[] calldata dnas) external view returns (address[] memory);
}

/*
| Function                  | Mint State | Payment       | Batch  | Specify Recipient |
|---------------------------|------------|---------------|--------|-------------------|
| mint(dna)                 | Public     | mintPrice     | No     | No                |
| mintTo(to, dna)           | Public     | mintPrice     | No     | Yes               |
| mintBatch(dnas)           | Public     | mintPrice * N | Yes    | No                |
| mintBatchTo(to, dnas)     | Public     | mintPrice * N | Yes    | Yes               |
*/

/**
 * @title IOpenAvatarGen0TokenMintRead
 * @notice An interface for reading OpenAvatar minting state.
 */
interface IOpenAvatarGen0TokenMintRead {
  /////////////////////////////////////////////////////////////////////////////
  // Supply
  /////////////////////////////////////////////////////////////////////////////
  function supplySoftCap() external view returns (uint16);

  function supplyHardCap() external view returns (uint16);

  /////////////////////////////////////////////////////////////////////////////
  // Mint Price
  /////////////////////////////////////////////////////////////////////////////

  function getMintPrice() external view returns (uint);

  /////////////////////////////////////////////////////////////////////////////
  // Mint State
  /////////////////////////////////////////////////////////////////////////////

  function isMinted(bytes32 dna) external view returns (bool);

  function isMintedEach(bytes32[] calldata dnas) external view returns (bool[] memory);
}

/**
 * @title IOpenAvatarGen0TokenMintWrite
 * @notice An interface for minting OpenAvatars.
 */
interface IOpenAvatarGen0TokenMintWrite {
  /////////////////////////////////////////////////////////////////////////////
  // Mint
  /////////////////////////////////////////////////////////////////////////////
  function mint(bytes32 dna) external payable;

  function mintTo(address to, bytes32 dna) external payable;

  function mintBatch(bytes32[] calldata dnas) external payable;

  function mintBatchTo(address to, bytes32[] calldata dnas) external payable;
}

/**
 * @title IOpenAvatarGen0TokenMintAdmin
 * @notice An interface allowing the public mint price to be updated.
 */
interface IOpenAvatarGen0TokenMintAdmin {
  /////////////////////////////////////////////////////////////////////////////
  // Mint Price
  /////////////////////////////////////////////////////////////////////////////
  function setMintPrice(uint val) external;
}

/**
 * @title IOpenAvatarGen0TokenMint
 * @notice The mint interfaces for OpenAvatarGen0Token.
 */
interface IOpenAvatarGen0TokenMint is
  IOpenAvatarGen0TokenMintRead,
  IOpenAvatarGen0TokenMintWrite,
  IOpenAvatarGen0TokenMintAdmin
{

}

/**
 * @title IOpenAvatar
 * @dev The OpenAvatar interface.
 */
interface IOpenAvatarGen0Token is
  IOpenAvatar,
  IOpenAvatarGen0TokenMetadata,
  IOpenAvatarGen0TokenDNA,
  IOpenAvatarGen0TokenMint
{

}
