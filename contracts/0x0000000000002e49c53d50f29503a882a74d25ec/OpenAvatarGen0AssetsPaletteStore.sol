// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IOpenAvatarGen0AssetsPaletteStore, UploadPaletteBatchInput, UploadPaletteInput} from '../interfaces/assets/IOpenAvatarGen0AssetsPaletteStore.sol';
import {FuseGuard} from '../lib/FuseGuard.sol';
import {KeepAlive} from '../lib/KeepAlive.sol';

/**
 * @title OpenAvatarGen0AssetsPaletteStore
 * @dev This contract stores color palettes by (code, index).
 * @dev All palettes of a given code should be the same length.
 */
contract OpenAvatarGen0AssetsPaletteStore is IOpenAvatarGen0AssetsPaletteStore, FuseGuard, KeepAlive {
  /// @dev Error for invalid palette code.
  error InvalidPaletteCode(uint8 code);
  /// @dev Error for empty palette array.
  error EmptyPaletteArray();
  /// @dev Error for invalid palette index.
  error PaletteIndexOutOfBounds(uint8 code, uint8 index);
  /// @dev Error for palette already exists.
  error PaletteAlreadyExists(uint8 code, uint8 index);
  /// @dev Error for invalid palette length.
  error InvalidPaletteLength(uint length);
  /// @dev Error for invalid transparent color code.
  error InvalidTransparentColorCode(bytes4 code);
  /// @dev Event emitted when the fuse is burned to disable uploading a new palette.
  event FuseBurnedCanUploadPalette();
  /// @dev Event emitted when a palette is uploaded.
  event PaletteUpload(uint8 code, uint8 index);

  /// @dev RGBA color depth.
  uint8 public constant DEPTH = 4;
  /// @dev Whether the canvas has an alpha channel.
  bool public constant HAS_ALPHA_CHANNEL = true;

  /////////////////////////////////////////////////////////////////////////////
  // Internal Data Structures
  /////////////////////////////////////////////////////////////////////////////

  /// @dev The color palettes.
  /// @dev 5D array
  ///        bytes4 -----------> (red, green, blue, alpha) color
  ///        bytes4[] ---------> A color palette
  ///        bytes4[][] -------> A set of color palettes (for a palette code)
  ///        bytes4[][][] -----> All the color palette sets for all the palette codes
  bytes4[][][] public palettes;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for uploading a palette.
  bool public fuseBurnedCanUploadPalette = false;

  constructor(address ownerProxy) {
    // will be deployed by ImmutableCreate2Factory and then transferred to the configured owner
    // using a proxy allows for using same bytecode in test and prod

    address wantOwner = Ownable(ownerProxy).owner();
    if (owner() != wantOwner) {
      transferOwnership(wantOwner);
    }
  }

  /**
   * @notice Return whether the canvas has an alpha channel.
   * @return Whether the canvas has an alpha channel.
   */
  function hasAlphaChannel() external pure override returns (bool) {
    return HAS_ALPHA_CHANNEL;
  }

  /**
   * @notice Return the number of bytes per pixel.
   * @return The number of bytes per pixel.
   */
  function getBytesPerPixel() public pure override returns (uint8) {
    return DEPTH;
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
      // palette
      interfaceId == 0x5577825f || // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStoreRead.
      interfaceId == 0x9c9764e9 || // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStoreWrite.
      interfaceId == 0xc9e0e6b6; // ERC165 interface ID for IOpenAvatarGen0AssetsPaletteStore.
  }

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Burn the fuse to permanently disable uploading a new palette.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanUploadPalette() external onlyOwner {
    if (fuseBurnedCanUploadPalette) return;
    fuseBurnedCanUploadPalette = true;
    emit FuseBurnedCanUploadPalette();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable uploading a new palette.
   * @return Whether the fuse is burned to permanently disable uploading a new palette.
   */
  function isFuseBurnedCanUploadPalette() external view returns (bool) {
    return fuseBurnedCanUploadPalette;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Palettes
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Get the number of palette codes.
   */
  function getNumPaletteCodes() external view override returns (uint) {
    return palettes.length;
  }

  /**
   * @notice Get the number of palettes for the given layer and index.
   * @param code The palette code.
   */
  function getNumPalettes(uint8 code) external view override returns (uint) {
    return (code < palettes.length) ? palettes[code].length : 0;
  }

  /**
   * @notice Get the palette for the given palette code and index.
   * @param code The code for which to get the palette.
   * @param index The index of the palette to get.
   * @return The palette for the given layer, pattern, index.
   * @dev Returns an empty array if the palette does not exist.
   */
  function getPalette(uint8 code, uint8 index) external view override returns (bytes4[] memory) {
    if (code < palettes.length) {
      bytes4[][] storage codePalettes = palettes[code];
      if (index < codePalettes.length) {
        return codePalettes[index];
      }
    }
    // return empty array if not found
    return new bytes4[](0);
  }

  /**
   * @notice Store the given palette in the contract
   * @param input The palette to store.
   */
  function uploadPalette(UploadPaletteInput calldata input) external override onlyOwner {
    // check fuse
    if (fuseBurnedCanUploadPalette) revert OperationBlockedByBurnedFuse();

    // should always include transparent (will revert later if index 0 is not transparent)
    if (input.palette.length == 0) revert InvalidPaletteLength(input.palette.length);

    // Base Case: palettes[code] does not exist yet
    if (input.code == palettes.length) {
      // create new array of palettes
      palettes.push(new bytes4[][](0));
    }
    // Append Case: palettes[code] exists
    if (input.code < palettes.length) {
      bytes4[][] storage codePalettes = palettes[input.code];

      // 3 cases:
      // 1. index == length, append (happy path)
      // 2. index < length, revert
      // 3. index > length, revert
      uint ct = codePalettes.length;
      if (input.index == ct) {
        // append
        // check that the first color is transparent
        if (input.palette[0] != 0x00000000) {
          revert InvalidTransparentColorCode(input.palette[0]);
        }
        // TODO: verify length of each palette matches the same as the first
        // palette uploaded for that code
        codePalettes.push(input.palette);
        emit PaletteUpload(input.code, input.index);
      } else if (input.index < ct) {
        // already exists
        revert PaletteAlreadyExists(input.code, input.index);
      } else {
        // index > ct out of bounds
        revert PaletteIndexOutOfBounds(input.code, input.index);
      }
    } else {
      // out of bounds
      revert InvalidPaletteCode(input.code);
    }
  }

  /**
   * @notice Store the given palettes in the contract
   * @param input The paletted to store.
   */
  function uploadPaletteBatch(UploadPaletteBatchInput calldata input) external override onlyOwner {
    _uploadPaletteBatch(input);
  }

  /**
   * @notice Store the given palettes in the contract
   * @param input The paletted to store.
   */
  function _uploadPaletteBatch(UploadPaletteBatchInput calldata input) internal {
    // check fuse
    if (fuseBurnedCanUploadPalette) revert OperationBlockedByBurnedFuse();

    // should always include transparent (will revert later if index 0 is not transparent)
    if (input.palettes.length == 0) revert EmptyPaletteArray();

    // Base Case: palettes[code] does not exist yet
    if (input.code == palettes.length) {
      // create new array of palettes
      palettes.push(new bytes4[][](0));
    }
    // Append Case: palettes[code] exists
    if (input.code < palettes.length) {
      bytes4[][] storage codePalettes = palettes[input.code];

      // 3 cases:
      // 1. index == length, append (happy path)
      // 2. index < length, revert
      // 3. index > length, revert
      uint ct = codePalettes.length;
      if (input.fromIndex == ct) {
        // append all palettes
        uint len = input.palettes.length;
        for (uint i = 0; i < len; ) {
          bytes4[] calldata palette = input.palettes[i];
          // check that the first color is transparent
          if (palette[0] != 0x00000000) {
            revert InvalidTransparentColorCode(palette[0]);
          }
          // TODO: verify length of each palette matches?
          codePalettes.push(palette);
          emit PaletteUpload(input.code, uint8(i));
          unchecked {
            ++i;
          }
        }
      } else if (input.fromIndex < ct) {
        // already exists
        revert PaletteAlreadyExists(input.code, input.fromIndex);
      } else {
        // index > ct out of bounds
        revert PaletteIndexOutOfBounds(input.code, input.fromIndex);
      }
    } else {
      // out of bounds
      revert InvalidPaletteCode(input.code);
    }
  }

  /**
   * @notice Batch upload multiple palette batches.
   * @param inputs The palette batches to upload.
   */
  function uploadPaletteBatches(UploadPaletteBatchInput[] calldata inputs) external override onlyOwner {
    uint len = inputs.length;
    for (uint i = 0; i < len; ) {
      _uploadPaletteBatch(inputs[i]);
      unchecked {
        ++i;
      }
    }
  }
}
