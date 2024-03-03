// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IOpenAvatarGen0AssetsPatternStore, OptionalPatternHeader, PatternHeader, PatternBlob, UploadPatternInput} from '../interfaces/assets/IOpenAvatarGen0AssetsPatternStore.sol';
import {OpenAvatarGen0AssetsCanvasStore} from './OpenAvatarGen0AssetsCanvasStore.sol';
import {OpenAvatarGen0AssetsPaletteStore} from './OpenAvatarGen0AssetsPaletteStore.sol';

/**
 * @title OpenAvatarGen0AssetsPatternStore
 * @dev This contract stores assets via:
 * - canvas
 * - layer
 * - pattern
 * and for palettes, by:
 * - palette code
 * - palette
 */
contract OpenAvatarGen0AssetsPatternStore is
  IOpenAvatarGen0AssetsPatternStore,
  OpenAvatarGen0AssetsCanvasStore,
  OpenAvatarGen0AssetsPaletteStore
{
  /// @dev Event emitted when the fuse is burned to disable adding a new layer.
  event FuseBurnedCanAddLayer();
  /// @dev Event emitted when the fuse is burned to disable uploading a pattern.
  event FuseBurnedCanUploadPattern();
  /// @dev Event emitted when a layer is added to a canvas.
  event LayerAdd(uint8 canvasId, uint8 layer);
  /// @dev Event emitted when a pattern is uploaded.
  event PatternUpload(uint8 canvasId, uint8 layer, uint8 pattern);

  /// @dev Revert error when layer already exists.
  error LayerAlreadyExists(uint8 canvasId, uint8 layer);
  /// @dev Revert error when layer index is out of bounds.
  error LayerIndexOutOfBounds(uint8 canvasId, uint8 layer);
  /// @dev Revert error when pattern has invalid length.
  error InvalidPatternLength(uint width, uint height, uint length);
  /// @dev Revert error when pattern already exists.
  error PatternAlreadyExists(uint8 canvasId, uint8 layer, uint8 index);
  /// @dev Revert error when pattern index is out of bounds.
  error PatternIndexOutOfBounds(uint8 canvasId, uint8 layer, uint8 index);
  /// @dev Revert error when palette code does not exist.
  error UnknownPaletteCode(uint8 code);

  /////////////////////////////////////////////////////////////////////////////
  // Internal Data Structures
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Each pattern has a corresponding header describing the pattern data
  /// @dev Every pattern is an arbitrary blob of bytes
  mapping(uint => PatternBlob[][]) public patterns;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for adding a new layer.
  bool public fuseBurnedCanAddLayer = false;
  /// @dev Flag to indicate if the fuse has been burned for uploading a pattern.
  bool public fuseBurnedCanUploadPattern = false;

  // solhint-disable-next-line no-empty-blocks
  constructor(
    address ownerProxy
  ) OpenAvatarGen0AssetsCanvasStore(ownerProxy) OpenAvatarGen0AssetsPaletteStore(ownerProxy) {}

  /////////////////////////////////////////////////////////////////////////////
  // ERC-165: Standard Interface Detection
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Checks if the contract supports an interface.
   * @param interfaceId The interface identifier, as specified in ERC-165.
   * @return True if the contract supports interfaceID, false otherwise.
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(OpenAvatarGen0AssetsCanvasStore, OpenAvatarGen0AssetsPaletteStore) returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // canvas
      interfaceId == 0x91411495 || // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStoreRead.
      interfaceId == 0x4d4a1c57 || // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStoreWrite.
      interfaceId == 0xdc0b08c2 || // ERC165 interface ID for IOpenAvatarGen0AssetsCanvasStore.
      // palette
      interfaceId == 0x5577825f || // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStoreRead.
      interfaceId == 0x9c9764e9 || // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStoreWrite.
      interfaceId == 0xc9e0e6b6 || // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStore.
      // pattern
      interfaceId == 0x32c8b38e || // ERC165 interface ID for IOpenAvatarGen0AssetsPatternStoreRead.
      interfaceId == 0xcd89a9e1 || // ERC165 interface ID for IOpenAvatarGen0AssetsPatternStoreWrite.
      interfaceId == 0xff411a6f; // ERC165 interface ID for IOpenAvatarGen0AssetsPatternStore.
  }

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Burn the fuse to permanently disable adding a new layer.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanAddLayer() external onlyOwner {
    if (fuseBurnedCanAddLayer) return;
    fuseBurnedCanAddLayer = true;
    emit FuseBurnedCanAddLayer();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable adding a new layer.
   * @return Whether the fuse is burned to permanently disable adding a new layer.
   */
  function isFuseBurnedCanAddLayer() external view returns (bool) {
    return fuseBurnedCanAddLayer;
  }

  /**
   * @notice Burn the fuse to permanently disable uploading a new pattern.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanUploadPattern() external onlyOwner {
    if (fuseBurnedCanUploadPattern) return;
    fuseBurnedCanUploadPattern = true;
    emit FuseBurnedCanUploadPattern();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable uploading a new pattern.
   * @return Whether the fuse is burned to permanently disable uploading a new pattern.
   */
  function isFuseBurnedCanUploadPattern() external view returns (bool) {
    return fuseBurnedCanUploadPattern;
  }

  /**************************************************************************
   * Helpers
   *************************************************************************/

  /**
   * @notice Pack four uint8 values into a single uint32.
   * @param a The first uint8 value.
   * @param b The second uint8 value.
   * @param c The third uint8 value.
   * @param d The fourth uint8 value.
   * @param e The fifth uint8 value.
   * @return The packed uint40 value.
   */
  function packUint40(uint8 a, uint8 b, uint8 c, uint8 d, uint8 e) public pure returns (uint40) {
    return (uint40(a) << 32) | (uint40(b) << 24) | (uint40(c) << 16) | (uint40(d) << 8) | uint40(e);
  }

  /**************************************************************************
   * Layers
   *************************************************************************/

  /**
   * @notice Get the number of layers stored in the contract.
   * @param canvasId The canvas for which to get the pattern data.
   * @return The number of layers stored in the contract.
   */
  function getNumLayers(uint8 canvasId) public view override returns (uint) {
    return patterns[canvasId].length;
  }

  /**
   * @notice Add a new layer to the contract. The layer must not already exist. Layer indices may be skipped.
   * @param canvasId The canvas for which to get the pattern data.
   * @param layer The layer to add.
   * @dev This function is only callable by the contract owner.
   */
  function addLayer(uint8 canvasId, uint8 layer) public override onlyOwner {
    if (fuseBurnedCanAddLayer) revert OperationBlockedByBurnedFuse();
    if (!canvasExists[canvasId]) revert CanvasDoesNotExist(canvasId);
    unchecked {
      // layers can be skipped when adding to reserve for later
      // so we need to fill in the skipped layers with empty arrays
      PatternBlob[][] storage canvasPatterns = patterns[canvasId];
      while (canvasPatterns.length < layer + 1) {
        canvasPatterns.push(new PatternBlob[](0));
      }

      // now we have backfilled the layers, so procede with the main data
      PatternBlob[] storage patternsArrayForNewLayer = canvasPatterns[layer];
      if (patternsArrayForNewLayer.length == 0) {
        // transparent means no height/width/offsets
        // transparent layer has all zeros
        // transparent pattern is empty bytes
        patternsArrayForNewLayer.push(PatternBlob(PatternHeader(0, 0, 0, 0, 0), new bytes(0)));
        emit LayerAdd(canvasId, layer);
      } else {
        revert LayerAlreadyExists(canvasId, layer);
      }
    }
  }

  /**
   * @notice Add multiple layers to the contract. The layers must not already exist. Layer indices may be skipped.
   * @param canvasId The canvas for which to get the pattern data.
   * @param layers_ The layers to add.
   * @dev This function is only callable by the contract owner.
   */
  function addLayers(uint8 canvasId, uint8[] calldata layers_) public override onlyOwner {
    if (!canvasExists[canvasId]) revert CanvasDoesNotExist(canvasId);
    uint len = layers_.length;
    for (uint i = 0; i < len; ) {
      addLayer(canvasId, layers_[i]);
      unchecked {
        ++i;
      }
    }
  }

  /**************************************************************************
   * Patterns
   *************************************************************************/

  /**
   * @notice Get the number of patterns for the given layer and index.
   * @param canvasId The canvas for which to get the pattern data.
   * @param layer The layer for which to get the number of patterns.
   * @return The number of patterns for the given layer and index.
   */
  function getNumPatterns(uint8 canvasId, uint8 layer) public view override returns (uint) {
    PatternBlob[][] storage canvasPatterns = patterns[canvasId];
    if (layer < canvasPatterns.length) {
      return canvasPatterns[layer].length;
    } else {
      // we have a choice to return 0 or revert
      // since any valid layer always has a transparent pattern, we can return 0
      // and callers can use that to determine if the layer exists without handling
      // a revert
      return 0;
    }
  }

  /**
   * @notice Get the pattern header for the given layer and index.
   * @param canvasId The canvas for which to get the pattern data.
   * @param layer The layer for which to get the pattern header.
   * @param index The index of the pattern header to get.
   * @return The pattern header for the given layer and index.
   */
  function getPatternHeader(
    uint8 canvasId,
    uint8 layer,
    uint8 index
  ) external view override returns (OptionalPatternHeader memory) {
    PatternBlob[][] storage canvasPatterns = patterns[canvasId];
    if (layer < canvasPatterns.length) {
      PatternBlob[] storage layerPatterns = canvasPatterns[layer];
      if (index < layerPatterns.length) {
        return OptionalPatternHeader(true, layerPatterns[index].header);
      }
    }
    return OptionalPatternHeader(false, PatternHeader(0, 0, 0, 0, 0));
  }

  /**
   * @notice Get the pattern for the given layer and index.
   * @param canvasId The canvas for which to get the pattern data.
   * @param layer The layer for which to get the pattern data.
   * @param index The index of the pattern to get.
   * @return The pattern for the given layer and index.
   */
  function getPatternData(uint8 canvasId, uint8 layer, uint8 index) public view override returns (bytes memory) {
    PatternBlob[][] storage canvasPatterns = patterns[canvasId];
    if (layer < canvasPatterns.length) {
      PatternBlob[] storage layerPatterns = canvasPatterns[layer];
      if (index < layerPatterns.length) {
        return layerPatterns[index].data;
      }
    }
    return new bytes(0);
  }

  /**
   * @notice Store the given pattern in the contract.
   * @param input The input.
   */
  function uploadPattern(UploadPatternInput calldata input) public override onlyOwner {
    if (fuseBurnedCanUploadPattern) revert OperationBlockedByBurnedFuse();
    if (!canvasExists[input.canvasId]) revert CanvasDoesNotExist(input.canvasId);
    // consistency checks
    if (input.data.length != uint(input.width) * uint(input.height)) {
      revert InvalidPatternLength(input.width, input.height, input.data.length);
    }
    if (input.paletteCode < palettes.length) {
      PatternBlob[][] storage canvasPatterns = patterns[input.canvasId];
      if (input.layer < canvasPatterns.length) {
        PatternBlob[] storage layerPatterns = canvasPatterns[input.layer];
        uint ct = layerPatterns.length;

        // 3 cases:
        // 1. index == length, append (happy path)
        // 2. index < length, revert
        // 3. index > length, revert
        if (input.index == ct) {
          // append
          layerPatterns.push(
            PatternBlob(
              PatternHeader(input.width, input.height, input.offsetX, input.offsetY, input.paletteCode),
              input.data
            )
          );

          emit PatternUpload(input.canvasId, input.layer, input.index);
        } else if (input.index < ct) {
          // already exists
          revert PatternAlreadyExists(input.canvasId, input.layer, input.index);
        } else {
          // out of bounds
          revert PatternIndexOutOfBounds(input.canvasId, input.layer, input.index);
        }
      } else {
        revert LayerIndexOutOfBounds(input.canvasId, input.layer);
      }
    } else {
      revert UnknownPaletteCode(input.paletteCode);
    }
  }

  /**
   * @notice Batch upload multiple patterns.
   * @param inputs The uploadPattern inputs.
   */
  function uploadPatterns(UploadPatternInput[] calldata inputs) public override onlyOwner {
    if (fuseBurnedCanUploadPattern) revert OperationBlockedByBurnedFuse();
    uint len = inputs.length;
    for (uint i = 0; i < len; ) {
      uploadPattern(inputs[i]);
      unchecked {
        ++i;
      }
    }
  }
}
