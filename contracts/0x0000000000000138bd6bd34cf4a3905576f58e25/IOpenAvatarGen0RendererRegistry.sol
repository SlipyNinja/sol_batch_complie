// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

/**
 * @title IOpenAvatarGen0RendererRegistryRead
 * @dev An interface for reading registered OpenAvatar renderers.
 */
interface IOpenAvatarGen0RendererRegistryRead {
  /////////////////////////////////////////////////////////////////////////////
  // Read
  /////////////////////////////////////////////////////////////////////////////

  function getNumRenderers() external view returns (uint);

  function getRendererByKey(string calldata key) external view returns (address);

  function getRendererByDNA(bytes32 dna) external view returns (address);

  function getDefaultRenderer() external view returns (address);
}

/**
 * @title IOpenAvatarGen0RendererRegistryWrite
 * @dev An interface for registering OpenAvatar renderers.
 */
interface IOpenAvatarGen0RendererRegistryWrite {
  /////////////////////////////////////////////////////////////////////////////
  // Write
  /////////////////////////////////////////////////////////////////////////////

  function addRenderer(string calldata key, address _renderer) external;

  function setDefaultRendererByKey(string calldata key) external;
}

/**
 * @title IOpenAvatarGen0RendererRegistry
 * @dev An interface for registering OpenAvatar renderers.
 */
interface IOpenAvatarGen0RendererRegistry is IOpenAvatarGen0RendererRegistryRead, IOpenAvatarGen0RendererRegistryWrite {

}
