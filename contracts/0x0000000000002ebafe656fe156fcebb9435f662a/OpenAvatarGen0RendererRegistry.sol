// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {ENSReverseClaimer} from './core/lib/ENSReverseClaimer.sol';
import {FuseGuard} from './core/lib/FuseGuard.sol';
import {IOpenAvatarGen0TokenDNA} from './IOpenAvatarGen0Token.sol';
import {IOpenAvatarGen0RendererRegistry} from './IOpenAvatarGen0RendererRegistry.sol';
import {IOpenAvatarGen0TextRecords} from './IOpenAvatarGen0TextRecords.sol';
import {OpenAvatarGenerationZero} from './OpenAvatarGenerationZero.sol';

/**
 * @title OpenAvatarGen0RendererRegistry
 * @author Cory Gabrielsen (cory.eth)
 *
 * @notice An append-only registry of OpenAvatarGen0Renderer contracts.
 * @dev An append-only registry of renderer addresses.
 *
 *
 * ----------------------------------------------------------------------------
 * Renderer Registry
 * ----------------------------------------------------------------------------
 * A separate `OpenAvatarGen0RendererRegistry` contract is used to register
 * Renderers for use by the `OpenAvatarGen0Token` contract.
 *
 * The `OpenAvatarGen0Token` contract determines which Renderer to use for a
 * given token by delegating to the `OpenAvatarGen0RendererRegistry` contract.
 *
 * Default Renderer:
 * The registry maintains a concept of "default" Renderer, which may be
 * modified by the contract owner.
 *
 * Token Owners may optionally override the default Renderer for their token by
 * writing a valid 'gen0.renderer` text record to the
 * `OpenAvatarGen0TextRecords` contract.
 *
 * When the ERC721::tokenURI method is called, the Renderer (token default if
 * exists, otherwise registry default) is called to render the URI.
 *
 * The net effect is that rendering is invariant and onchain.
 *
 * If further Renderers are made available by the registry owner, token owners
 * may opt-in to those upgrades either in general (by not setting a token
 * default) or explicit choice (by setting their corresponding text record).
 *
 * This "soft-upgradeability" can be sunset by burning the registry fuse which
 * blocks further additions, thereby making the list of available Renderers
 * fully immutable.
 *
 * At launch, two Renderers are provided, described below.
 *
 *
 * ----------------------------------------------------------------------------
 * 'base' Renderer
 * ----------------------------------------------------------------------------
 * A base Renderer is provided with the key "base".
 *
 * The 'base' Renderer renders the Avatar with transparent background as a
 * forward-facing sprite.
 *
 *
 * ----------------------------------------------------------------------------
 * 'pfp' Renderer
 * ----------------------------------------------------------------------------
 * A Profile Picture Renderer is provided with the key "pfp".
 *
 * The 'pfp' Renderer renders the Avatar with a configurable background color
 * determined by the 'gen0.renderer.pfp.background-color' text record, which
 * should be a valid RGB hex color code (e.g. "#ff0000" for red).
 *
 * Further, the 'pfp' Renderer provides the option of masking the Avatar
 * below the neck to create a "floating head" effect. This can be configured
 * by setting the `gen0.renderer.pfp.mask` text record to "below-the-neck".
 *
 * The Profile Picture Renderer is a demonstration of combining the OpenAvatar
 * building blocks together to create dynamic, owner-customizable behavior. It
 * utilizes onchain assets, onchain rendering, and onchain text records to
 * render a customizable Avatar pfp.
 *
 * This pattern is permissionless.
 */
contract OpenAvatarGen0RendererRegistry is
  IOpenAvatarGen0RendererRegistry,
  OpenAvatarGenerationZero,
  FuseGuard,
  ENSReverseClaimer
{
  /// @dev Event emitted when default renderer is changed.
  event DefaultRendererChange(string indexed key);
  /// @dev Event emitted when the fuse is burned to disable adding renderers.
  event FuseBurnedCanAddRenderer();
  /// @dev Event emitted when a renderer is added.
  event RendererAdd(string indexed key, address renderer);

  /// @dev Error when a component is already initialized.
  error AlreadyInitialized();
  /// @dev Event emitted when an interface is not supported.
  error InterfaceUnsupported(address contractAddress, bytes4 interfaceId);
  /// @dev Revert error when renderer index is out of bounds.
  error RendererDoesNotExist(string key);
  /// @dev Revert error when renderer already exists.
  error RendererAlreadyExists(address renderer);
  /// @dev Event emitted when a renderer key already exists.
  error RendererKeyAlreadyExists(string key);
  /// @dev Revert error when renderer key is empty.
  error RendererKeyCannotBeEmpty();

  /////////////////////////////////////////////////////////////////////////////
  // Dependencies
  /////////////////////////////////////////////////////////////////////////////
  /// @dev The ERC-165 interface id for the OpenAvatarGen0Renderer (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_RENDERER = 0xb93e4881;
  /// @dev The ERC-165 interface id for the OpenAvatarGen0TextRecords ERC-634 text() (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_TEXT = 0x59d1d43c;

  /// @dev The text key for the renderer.
  string public constant TEXT_KEY_RENDERER = 'gen0.renderer';

  /// @dev The OpenAvatarGen0TextRecords dependency.
  IOpenAvatarGen0TextRecords public openAvatarGen0TextRecords;

  /// @dev The default renderer index.
  string private defaultRendererKey;

  /// @dev The list of renderers.
  mapping(string key => address renderer) public renderers;
  /// @dev The list of renderer keys.
  string[] public rendererKeys;
  /// @dev The list of renderer keys by address.
  mapping(address renderer => bool) public isRenderer;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for changing the mint state.
  bool public fuseBurnedCanAddRenderer = false;

  /////////////////////////////////////////////////////////////////////////////
  // Initialization
  /////////////////////////////////////////////////////////////////////////////

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
      // IOpenAvatar
      interfaceId == 0xfdf02ac8 || // ERC165 interface ID for IOpenAvatarGeneration.
      interfaceId == 0x7b65147c || // ERC165 interface ID for IOpenAvatarSentinel.
      interfaceId == 0x86953eb4 || // ERC165 interface ID for IOpenAvatar.
      // IOpenAvatarGen0RendererRegistry
      interfaceId == 0x8646df82; // ERC165 interface ID for IOpenAvatarGen0RendererRegistry
  }

  /////////////////////////////////////////////////////////////////////////////
  // Initialize Dependencies
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Initialize the contract.
   * @param openAvatarGen0TextRecords_ The address of the OpenAvatarGen0TextRecords contract.
   */
  function initialize(address openAvatarGen0TextRecords_) external onlyOwner {
    setOpenAvatarGen0TextRecords(openAvatarGen0TextRecords_);
  }

  /**
   * @notice Check if the contract has been initialized.
   * @return True if the contract has been initialized, false otherwise.
   */
  function isInitialized() external view returns (bool) {
    return address(openAvatarGen0TextRecords) != address(0);
  }

  /**
   * @notice Get the OpenAvatarGen0TextRecords.
   * @return The address of the OpenAvatarGen0TextRecords.
   */
  function getOpenAvatarGen0TextRecords() external view returns (address) {
    return address(openAvatarGen0TextRecords);
  }

  /**
   * @notice Set the OpenAvatarGen0TextRecords address.
   * @param openAvatarGen0TextRecords_ The address of the OpenAvatarGen0TextRecords contract.
   */
  function setOpenAvatarGen0TextRecords(address openAvatarGen0TextRecords_) internal {
    // only set once
    if (address(openAvatarGen0TextRecords) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only text() interface is required
    if (!IERC165(openAvatarGen0TextRecords_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_TEXT)) {
      revert InterfaceUnsupported(openAvatarGen0TextRecords_, INTERFACE_ID_OPENAVATAR_GEN0_TEXT);
    }

    // set
    openAvatarGen0TextRecords = IOpenAvatarGen0TextRecords(openAvatarGen0TextRecords_);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Default renderer
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns the default Renderer address for all token ids.
   * @return The default Renderer address for all token ids.
   */
  function getDefaultRenderer() external view returns (address) {
    return renderers[defaultRendererKey];
  }

  /**
   * @notice Sets the default Renderer address for all token ids.
   * @param key The key of the Renderer to set as the default.
   */
  function setDefaultRendererByKey(string calldata key) external onlyOwner {
    // check if the key exists
    address renderer = renderers[key];
    if (renderer == address(0)) revert RendererDoesNotExist(key);
    // check if the key is the same as the current default
    bool isSame = (bytes(defaultRendererKey).length == bytes(key).length) &&
      (keccak256(bytes(defaultRendererKey)) == keccak256(bytes(key)));
    if (isSame) return;
    // set the new default
    defaultRendererKey = key;
    emit DefaultRendererChange(key);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Read
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns the number of renderers available.
   * @return The number of renderers available.
   */
  function getNumRenderers() external view returns (uint) {
    return rendererKeys.length;
  }

  /**
   * @notice Returns the keys of the renderers.
   * @return The keys of the renderers.
   */
  function getRendererKeys() external view returns (string[] memory) {
    return rendererKeys;
  }

  /**
   * @notice Returns the address of the renderer.
   * @return The address of the renderer or 0x0 if not found.
   */
  function getRendererByKey(string calldata key) external view returns (address) {
    return renderers[key];
  }

  /**
   * @notice Returns the Renderer address for a given DNA.
   * @param dna The dna to lookup.
   * @return The Renderer address for the given DNA.
   * @dev If the DNA has not been minted, this will revert.
   */
  function getRendererByDNA(bytes32 dna) public view returns (address) {
    address renderer = address(0);
    if (address(openAvatarGen0TextRecords) != address(0)) {
      string memory rendererKey = openAvatarGen0TextRecords.text(dna, TEXT_KEY_RENDERER);
      renderer = renderers[rendererKey];
    }
    if (renderer == address(0)) return renderers[defaultRendererKey];
    return renderer;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Write
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Pushes the address of the renderer to the end of the list.
   * @param key The key of the renderer.
   * @param renderer The address of the renderer.
   * @dev Only callable by owner. Reverts if the key already exists.
   */
  function addRenderer(string calldata key, address renderer) external onlyOwner {
    // fuse must not be burned
    if (fuseBurnedCanAddRenderer) revert OperationBlockedByBurnedFuse();

    // key must not be empty
    if (bytes(key).length == 0) revert RendererKeyCannotBeEmpty();

    // must support the interface
    if (!IERC165(renderer).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_RENDERER)) {
      revert InterfaceUnsupported(renderer, INTERFACE_ID_OPENAVATAR_GEN0_RENDERER);
    }

    // should not already exist
    if (renderers[key] != address(0)) revert RendererKeyAlreadyExists(key);
    // address should not already exist
    if (isRenderer[renderer]) revert RendererAlreadyExists(renderer);

    // add the renderer
    renderers[key] = renderer;
    rendererKeys.push(key);
    isRenderer[renderer] = true;
    emit RendererAdd(key, renderer);

    // set the default if it is empty
    if (bytes(defaultRendererKey).length == 0) {
      defaultRendererKey = key;
      emit DefaultRendererChange(key);
    }
  }

  /////////////////////////////////////////////////////////////////
  // Fuse - Can Add Renderer
  /////////////////////////////////////////////////////////////////

  /**
   * @notice Burn the fuse to permanently disable changing the public mint time.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanAddRenderer() external onlyOwner {
    if (fuseBurnedCanAddRenderer) return;
    fuseBurnedCanAddRenderer = true;
    emit FuseBurnedCanAddRenderer();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable changing the public mint time.
   * @return Whether the fuse is burned to permanently disable changing the public mint time.
   */
  function isFuseBurnedCanAddRenderer() external view returns (bool) {
    return fuseBurnedCanAddRenderer;
  }
}
