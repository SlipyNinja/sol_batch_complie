// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {OpenAvatarGen0AssetsCanvasStore} from './core/assets/OpenAvatarGen0AssetsCanvasStore.sol';
import {OpenAvatarGen0AssetsPaletteStore} from './core/assets/OpenAvatarGen0AssetsPaletteStore.sol';
import {OpenAvatarGen0AssetsPatternStore} from './core/assets/OpenAvatarGen0AssetsPatternStore.sol';
import {ENSReverseClaimer} from './core/lib/ENSReverseClaimer.sol';
import {IOpenAvatarGen0Assets} from './IOpenAvatarGen0Assets.sol';
import {OpenAvatarGenerationZero} from './OpenAvatarGenerationZero.sol';

/**
 * @title OpenAvatarGen0Assets
 * @author Cory Gabrielsen (cory.eth)
 *
 * @dev This contract is responsible for storing OpenAvatar art assets and
 *      metadata. The art was created by hand by the contract author.
 *
 * Immutability:
 * - This contract references no other contracts
 * - All assets are stored in append-only arrays.
 * - Once uploaded, no asset can be modified or deleted.
 * - So, asset references are immutable and reads are invariant.
 * - Fuses can be burned to prevent contract owner uploading further assets.
 * - If all fuses are burned, no further assets can be uploaded and storage is
 *   effectively frozen.
 *
 * Terminology:
 * Colors are stored as color palettes.
 * Patterns are byte arrays that reference colors in a palette.
 *
 * - Palettes:
 *   - A "palette" is an array of RGBA colors (bytes4[]).
 *   - A "palette code" defines an array of palettes (bytes4[][]).
 *
 * - Canvas
 *   - A "canvas" is an image canvas with header (uint8 id, uint8 height,
 *   uint8 width), and an array of layers.
 *
 * - Layer
 *   - A "layer" is a layer of a canvas, which references an array of patterns.
 *
 * - Pattern
 *  - A "pattern" is a byte array that references colors by index in a palette.
 *
 * Fuses:
 * - A fuse can be burned to prevent adding new canvases.
 * - A fuse can be burned to prevent adding new layers (for all canvases).
 * - A fuse can be burned to prevent adding new patterns (for all layers).
 * - A fuse can be burned to prevent adding new palettes (for all patterns).
 *
 * Solidity:
 * Due to C3 Linearization, we cannot "is" IOpenAvatarGen0Assets.
 * However, IOpenAvatarGen0Assets is indeed implemented fully by OpenAvatarGen0AssetsPatternStore.
 */
contract OpenAvatarGen0Assets is OpenAvatarGenerationZero, OpenAvatarGen0AssetsPatternStore, ENSReverseClaimer {
  // solhint-disable-next-line no-empty-blocks
  constructor(address ownerProxy) OpenAvatarGen0AssetsPatternStore(ownerProxy) {}

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
  ) public pure override(OpenAvatarGenerationZero, OpenAvatarGen0AssetsPatternStore) returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // IOpenAvatar
      interfaceId == 0xfdf02ac8 || // ERC165 interface ID for IOpenAvatarGeneration.
      interfaceId == 0x7b65147c || // ERC165 interface ID for IOpenAvatarSentinel.
      interfaceId == 0x86953eb4 || // ERC165 interface ID for IOpenAvatar.
      // assets
      interfaceId == 0x67bf31d1 || // ERC165 interface ID for IOpenAvatarGen0AssetsRead.
      interfaceId == 0x511ecd08 || // ERC165 interface ID for IOpenAvatarGen0AssetsWrite.
      interfaceId == 0x36a1fcd9 || // ERC165 interface ID for IOpenAvatarGen0Assets.
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
}
