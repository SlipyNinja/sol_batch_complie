// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {CanvasHeader, IOpenAvatarGen0AssetsCanvasStore} from '../interfaces/assets/IOpenAvatarGen0AssetsCanvasStore.sol';
import {FuseGuard} from '../lib/FuseGuard.sol';
import {KeepAlive} from '../lib/KeepAlive.sol';

/**
 * @title OpenAvatarGen0AssetsCanvasStore
 * @dev This contract stores canvas headers
 * @dev This contract is used for off-chain rendering
 */
contract OpenAvatarGen0AssetsCanvasStore is IOpenAvatarGen0AssetsCanvasStore, FuseGuard, KeepAlive {
  /// @dev Event emitted when a canvas is added.
  event CanvasAdd(uint8 id);

  /// @dev Event emitted when the fuse is burned to disable adding a new canvas.
  event FuseBurnedCanAddCanvas();

  /// @dev Rvert error when canvas already exists.
  error CanvasAlreadyExists(uint8 id);
  /// @dev Revert error when canvas does not exist.
  error CanvasDoesNotExist(uint8 id);
  /// @dev Revert error when canvas size is invalid.
  error InvalidCanvasSize(uint8 width, uint8 height);

  /// @dev The canvas bytes per pixel.
  /// @dev the only reason this is separate and named with CANVAS_ prefix is because
  // there is another one in PaletteStore and they conflict
  uint8 public constant CANVAS_BYTES_PER_PIXEL = 4; // RGBA

  /////////////////////////////////////////////////////////////////////////////
  // Internal Data Structures
  /////////////////////////////////////////////////////////////////////////////

  /// @dev The canvas ids.
  uint8[] public canvasIds;
  /// @dev The canvas headers.
  mapping(uint => CanvasHeader) public canvasHeaders;
  /// @dev Whether a canvas exists.
  mapping(uint => bool) public canvasExists;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for adding a new canvas.
  bool public fuseBurnedCanAddCanvas = false;

  constructor(address ownerProxy) {
    // will be deployed by ImmutableCreate2Factory and then transferred to the configured owner
    // using a proxy allows for using same bytecode in test and prod

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
  function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // canvas
      interfaceId == 0x91411495 || // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStoreRead.
      interfaceId == 0x4d4a1c57 || // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStoreWrite.
      interfaceId == 0xdc0b08c2; // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStore.
  }

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Burn the fuse to permanently disable adding a new canvas.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanAddCanvas() external onlyOwner {
    if (fuseBurnedCanAddCanvas) return;
    fuseBurnedCanAddCanvas = true;
    emit FuseBurnedCanAddCanvas();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable adding a new canvas.
   * @return Whether the fuse is burned to permanently disable adding a new canvas.
   */
  function isFuseBurnedCanAddCanvas() external view returns (bool) {
    return fuseBurnedCanAddCanvas;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Canvas
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Add a canvas to the store.
   * @param header The canvas header.
   */
  function addCanvas(CanvasHeader calldata header) external override onlyOwner {
    if (fuseBurnedCanAddCanvas) revert OperationBlockedByBurnedFuse();
    if (canvasExists[header.id]) revert CanvasAlreadyExists(header.id);
    if (header.width == 0 || header.height == 0) revert InvalidCanvasSize(header.width, header.height);
    canvasHeaders[header.id] = header;
    canvasIds.push(header.id);
    canvasExists[header.id] = true;
    emit CanvasAdd(header.id);
  }

  /**
   * @notice Return the number of canvases stored in the contract.
   * @return The number of canvases stored in the contract.
   */
  function hasCanvas(uint8 id) external view override returns (bool) {
    return canvasExists[id];
  }

  /**
   * @notice Return the canvas header.
   * @param id The canvas to query.
   * @return The canvas header.
   * @dev Returns all zeroes if the canvas does not exist.
   */
  function getCanvasHeader(uint8 id) external view override returns (CanvasHeader memory) {
    return canvasHeaders[id];
  }

  /**
   * @notice Return the number of canvases stored in the contract.
   * @return The number of canvases stored in the contract.
   */
  function getNumCanvasIds() external view override returns (uint) {
    return canvasIds.length;
  }

  /**
   * @notice Return the number of canvases stored in the contract.
   * @return The array of canvas ids stored in the contract.
   */
  function getCanvasIds() external view override returns (uint8[] memory) {
    return canvasIds;
  }

  /**
   * @notice Return the height of the canvas.
   * @param id The canvas to query.
   * @return The height of the canvas.
   */
  function getCanvasHeight(uint8 id) public view override returns (uint8) {
    return canvasHeaders[id].height;
  }

  /**
   * @notice Return the width of the canvas.
   * @param id The canvas to query.
   * @return The width of the canvas.
   */
  function getCanvasWidth(uint8 id) public view override returns (uint8) {
    return canvasHeaders[id].width;
  }

  /**
   * @notice Return the number of bytes in the canvas.
   * @param id The canvas to query.
   * @return The number of bytes in the canvas.
   */
  function getCanvasNumBytes(uint8 id) public view override returns (uint) {
    return CANVAS_BYTES_PER_PIXEL * uint(canvasHeaders[id].width) * uint(canvasHeaders[id].height);
  }

  /**
   * @notice Return the number of pixels in the canvas.
   * @param id The canvas to query.
   * @return The number of pixels in the canvas.
   */
  function getCanvasNumPixels(uint8 id) public view override returns (uint) {
    return uint(canvasHeaders[id].width) * uint(canvasHeaders[id].height);
  }
}
